using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using RFIDReaderAPI;
using RFIDReaderAPI.Interface;
using RFIDReaderAPI.Models;

namespace UHFHardwareBridge
{
    class Program : IAsynchronousMessage, IAsynBarCodeMessage, ISearchDevice
    {
        private static TcpListener _server;
        private static readonly List<TcpClient> _clients = new List<TcpClient>();
        private static readonly object _clientLock = new object();
        private static readonly JavaScriptSerializer _json = new JavaScriptSerializer();

        private static string _currentConnId = "";
        private static bool _isConnected = false;
        private static bool _isScanning = false;
        private static readonly Program _instance = new Program();

        static void Main(string[] args)
        {
            Console.OutputEncoding = Encoding.UTF8;
            Console.Title = "UHF Hardware Bridge - Hopeland RFID API (.NET 4.8)";
            Console.WriteLine("==================================================================");
            Console.WriteLine("        UHF HARDWARE BRIDGE SERVICE FOR FLUTTER DESKTOP          ");
            Console.WriteLine("        Native Drivers: RFIDReaderAPI.dll & Basic.dll            ");
            Console.WriteLine("==================================================================");

            int bridgePort = 9099;
            int p;
            if (args.Length > 0 && int.TryParse(args[0], out p)) bridgePort = p;

            try
            {
                _server = new TcpListener(IPAddress.Loopback, bridgePort);
                _server.Start();
                Console.WriteLine(string.Format("[{0:HH:mm:ss}] Bridge Server listening on 127.0.0.1:{1}...", DateTime.Now, bridgePort));
                Console.WriteLine("Waiting for Flutter Desktop App connection...");

                Thread acceptThread = new Thread(AcceptClientsLoop);
                acceptThread.IsBackground = true;
                acceptThread.Start();

                // Keep main thread alive
                while (true)
                {
                    Thread.Sleep(1000);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("Fatal Error in Bridge Server: " + ex.Message);
            }
        }

        private static void AcceptClientsLoop()
        {
            while (true)
            {
                try
                {
                    TcpClient client = _server.AcceptTcpClient();
                    lock (_clientLock)
                    {
                        _clients.Add(client);
                    }
                    Console.WriteLine(string.Format("[{0:HH:mm:ss}] Flutter Desktop App connected to Bridge!", DateTime.Now));

                    // Send initial status
                    Dictionary<string, object> initStatus = new Dictionary<string, object>();
                    initStatus["type"] = "status";
                    initStatus["connected"] = _isConnected;
                    initStatus["scanning"] = _isScanning;
                    initStatus["connId"] = _currentConnId;
                    BroadcastJson(initStatus);

                    Thread clientThread = new Thread(() => HandleClient(client));
                    clientThread.IsBackground = true;
                    clientThread.Start();
                }
                catch (Exception)
                {
                    break;
                }
            }
        }

        private static void HandleClient(TcpClient client)
        {
            NetworkStream stream = client.GetStream();
            StreamReader reader = new StreamReader(stream, Encoding.UTF8);

            try
            {
                while (client.Connected)
                {
                    string line = reader.ReadLine();
                    if (line == null) break;
                    if (string.IsNullOrEmpty(line.Trim())) continue;

                    ProcessFlutterCommand(line.Trim());
                }
            }
            catch (Exception)
            {
            }
            finally
            {
                lock (_clientLock)
                {
                    _clients.Remove(client);
                }
                client.Close();
                Console.WriteLine(string.Format("[{0:HH:mm:ss}] Flutter client disconnected.", DateTime.Now));
            }
        }

        private static void ProcessFlutterCommand(string jsonStr)
        {
            try
            {
                var cmdObj = _json.Deserialize<Dictionary<string, object>>(jsonStr);
                if (cmdObj == null || !cmdObj.ContainsKey("cmd")) return;

                string cmd = cmdObj["cmd"].ToString();

                switch (cmd.ToLower())
                {
                    case "connect":
                        HandleConnect(cmdObj);
                        break;
                    case "disconnect":
                        HandleDisconnect();
                        break;
                    case "start_inventory":
                        HandleStartInventory(cmdObj);
                        break;
                    case "stop_inventory":
                        HandleStopInventory();
                        break;
                    case "set_power":
                        HandleSetPower(cmdObj);
                        break;
                    case "read_bank":
                        HandleReadBank(cmdObj);
                        break;
                    case "write_bank":
                        HandleWriteBank(cmdObj);
                        break;
                    case "fast_write_epc":
                        HandleFastWriteEpc(cmdObj);
                        break;
                    case "lock":
                        HandleLock(cmdObj);
                        break;
                    case "kill":
                        HandleKill(cmdObj);
                        break;
                    case "search_lan":
                        RFIDReader.StartSearchDevice(_instance);
                        BroadcastLog("Started LAN device search...");
                        break;
                    case "set_gpo":
                        HandleSetGpo(cmdObj);
                        break;
                    case "ping":
                        Dictionary<string, object> pong = new Dictionary<string, object>();
                        pong["type"] = "pong";
                        pong["connected"] = _isConnected;
                        pong["scanning"] = _isScanning;
                        BroadcastJson(pong);
                        break;
                }
            }
            catch (Exception ex)
            {
                BroadcastLog("Bridge Process Error: " + ex.Message);
            }
        }

        private static void HandleConnect(Dictionary<string, object> obj)
        {
            string type = obj.ContainsKey("type") ? obj["type"].ToString() : "RS232";
            bool success = false;

            if (_isConnected) HandleDisconnect();

            try
            {
                if (type == "RS232")
                {
                    string port = obj.ContainsKey("port") ? obj["port"].ToString() : "COM3";
                    int baud = obj.ContainsKey("baud") ? Convert.ToInt32(obj["baud"]) : 115200;
                    string connParam = string.Format("{0}:{1}", port, baud);
                    BroadcastLog(string.Format("Opening Serial COM Port {0} @ {1} bps...", port, baud));

                    success = RFIDReader.CreateSerialConn(connParam, _instance, _instance);
                    if (success)
                    {
                        _currentConnId = connParam;
                        _isConnected = true;
                        BroadcastLog(string.Format("RS232 Connected successfully to {0}", connParam));
                    }
                    else
                    {
                        BroadcastLog(string.Format("Failed to open RS232 port {0}", connParam));
                    }
                }
                else if (type == "RS485")
                {
                    int addr = obj.ContainsKey("addr") ? Convert.ToInt32(obj["addr"]) : 1;
                    string port = obj.ContainsKey("port") ? obj["port"].ToString() : "COM3";
                    int baud = obj.ContainsKey("baud") ? Convert.ToInt32(obj["baud"]) : 115200;
                    string connParam = string.Format("{0}:{1}:{2}", addr, port, baud);
                    BroadcastLog(string.Format("Opening RS485 Address {0} on {1} @ {2} bps...", addr, port, baud));

                    success = RFIDReader.Create485Conn(connParam, _instance);
                    if (success)
                    {
                        _currentConnId = connParam;
                        _isConnected = true;
                        BroadcastLog(string.Format("RS485 Connected successfully to {0}", connParam));
                    }
                    else
                    {
                        BroadcastLog(string.Format("Failed to open RS485 on {0}", connParam));
                    }
                }
                else if (type == "TCP Client")
                {
                    string ip = obj.ContainsKey("ip") ? obj["ip"].ToString() : "192.168.1.116";
                    int port = obj.ContainsKey("port") ? Convert.ToInt32(obj["port"]) : 9090;
                    string connParam = string.Format("{0}:{1}", ip, port);
                    BroadcastLog(string.Format("Connecting TCP Client to {0}...", connParam));

                    success = RFIDReader.CreateTcpConn(connParam, _instance, _instance);
                    if (success)
                    {
                        _currentConnId = connParam;
                        _isConnected = true;
                        BroadcastLog(string.Format("TCP Connected successfully to {0}", connParam));
                    }
                    else
                    {
                        BroadcastLog(string.Format("Failed to connect TCP to {0}", connParam));
                    }
                }
                else if (type == "USB")
                {
                    BroadcastLog("Searching for USB HID RFID Reader...");
                    List<string> list = RFIDReader.GetUsbHidDeviceList();
                    if (list != null && list.Count > 0)
                    {
                        success = RFIDReader.CreateUsbConn(list[0], IntPtr.Zero, _instance);
                        if (success)
                        {
                            _currentConnId = list[0];
                            _isConnected = true;
                            BroadcastLog("USB HID Reader Connected successfully!");
                        }
                    }
                    else
                    {
                        BroadcastLog("No USB HID UHF Readers found.");
                    }
                }

                if (_isConnected)
                {
                    try
                    {
                        Dictionary<eGPO, eGPOState> gpoReset = new Dictionary<eGPO, eGPOState>();
                        gpoReset[eGPO._1] = eGPOState.Low;
                        gpoReset[eGPO._2] = eGPOState.Low;
                        gpoReset[eGPO._3] = eGPOState.Low;
                        gpoReset[eGPO._4] = eGPOState.Low;
                        RFIDReader._ReaderConfig.SetReaderGPOState(_currentConnId, gpoReset);
                    }
                    catch { }
                }

                Dictionary<string, object> res = new Dictionary<string, object>();
                res["type"] = "connect_result";
                res["success"] = success;
                res["connected"] = _isConnected;
                res["connId"] = _currentConnId;
                BroadcastJson(res);
            }
            catch (Exception ex)
            {
                BroadcastLog("Connection Exception: " + ex.Message);
            }
        }

        private static void HandleDisconnect()
        {
            try
            {
                if (_isScanning) HandleStopInventory();
                RFIDReader.CloseAllConnect();
            }
            catch { }
            finally
            {
                _isConnected = false;
                _isScanning = false;
                _currentConnId = "";
                BroadcastLog("Reader disconnected.");

                Dictionary<string, object> res = new Dictionary<string, object>();
                res["type"] = "status";
                res["connected"] = false;
                res["scanning"] = false;
                res["connId"] = "";
                BroadcastJson(res);
            }
        }

        private static void HandleStartInventory(Dictionary<string, object> obj)
        {
            if (!_isConnected || string.IsNullOrEmpty(_currentConnId))
            {
                BroadcastLog("Error: Reader not connected.");
                return;
            }

            try
            {
                int scanMode = obj.ContainsKey("mode") ? Convert.ToInt32(obj["mode"]) : 0;
                eAntennaNo antMask = eAntennaNo._1;
                if (obj.ContainsKey("antennas"))
                {
                    var antList = obj["antennas"] as System.Collections.ArrayList;
                    if (antList != null)
                    {
                        int maskVal = 0;
                        foreach (var a in antList)
                        {
                            int val = Convert.ToInt32(a);
                            if (val >= 1 && val <= 32) maskVal |= (1 << (val - 1));
                        }
                        if (maskVal > 0) antMask = (eAntennaNo)maskVal;
                    }
                }

                int ret = -1;
                if (scanMode == 0) // EPC Only
                {
                    ret = RFIDReader._Tag6C.GetEPC(_currentConnId, antMask, eReadType.Inventory);
                }
                else if (scanMode == 1) // EPC + TID
                {
                    ret = RFIDReader._Tag6C.GetEPC_TID(_currentConnId, antMask, eReadType.Inventory, 6, eMatchCode.None, "", 0);
                }
                else if (scanMode == 2) // EPC + TID + User
                {
                    ret = RFIDReader._Tag6C.GetEPC_TID_UserData(_currentConnId, antMask, eReadType.Inventory, 0, 4);
                }

                if (ret == 0)
                {
                    _isScanning = true;
                    BroadcastLog(string.Format("STARTED HARDWARE INVENTORY (AntMask: {0}, Mode: {1}) - RF LED IS ON!", (int)antMask, scanMode));
                }
                else
                {
                    BroadcastLog(string.Format("Failed to start hardware inventory. Return Code: {0}", ret));
                }

                Dictionary<string, object> res = new Dictionary<string, object>();
                res["type"] = "inventory_result";
                res["success"] = ret == 0;
                res["scanning"] = _isScanning;
                BroadcastJson(res);
            }
            catch (Exception ex)
            {
                BroadcastLog("Start Inventory Exception: " + ex.Message);
            }
        }

        private static void HandleStopInventory()
        {
            if (!_isConnected || string.IsNullOrEmpty(_currentConnId)) return;

            try
            {
                int ret = RFIDReader._Tag6C.Stop(_currentConnId);
                _isScanning = false;
                BroadcastLog("STOPPED HARDWARE INVENTORY.");

                Dictionary<string, object> res = new Dictionary<string, object>();
                res["type"] = "inventory_result";
                res["success"] = true;
                res["scanning"] = false;
                BroadcastJson(res);
            }
            catch (Exception ex)
            {
                BroadcastLog("Stop Inventory Exception: " + ex.Message);
            }
        }

        private static void HandleSetPower(Dictionary<string, object> obj)
        {
            if (!_isConnected) return;
            try
            {
                var powers = obj["powers"] as Dictionary<string, object>;
                if (powers != null)
                {
                    Dictionary<int, int> powerDic = new Dictionary<int, int>();
                    foreach (var kvp in powers)
                    {
                        int ant = int.Parse(kvp.Key);
                        int pwr = Convert.ToInt32(kvp.Value);
                        powerDic[ant] = pwr;
                    }
                    int ret = RFIDReader._RFIDConfig.SetANTPowerParam(_currentConnId, powerDic);
                    BroadcastLog(string.Format("Set Antenna Power result: {0}", ret == 0 ? "Success" : "Failed (" + ret + ")"));
                }
            }
            catch (Exception ex)
            {
                BroadcastLog("Set Power Exception: " + ex.Message);
            }
        }

        private static void HandleReadBank(Dictionary<string, object> obj)
        {
            if (!_isConnected) return;
            try
            {
                int bank = Convert.ToInt32(obj["bank"]);
                int offset = Convert.ToInt32(obj["offset"]);
                int count = Convert.ToInt32(obj["count"]);
                string match = obj.ContainsKey("match") ? obj["match"].ToString() : "";
                string pwd = obj.ContainsKey("pwd") ? obj["pwd"].ToString() : "00000000";

                eMatchCode mc = !string.IsNullOrEmpty(match) ? eMatchCode.EPC : eMatchCode.None;
                int ret = -1;

                if (bank == 1) // EPC
                {
                    ret = RFIDReader._Tag6C.GetEPC(_currentConnId, eAntennaNo._1, eReadType.Single, mc, match, 0, pwd);
                }
                else if (bank == 2) // TID
                {
                    ret = RFIDReader._Tag6C.GetEPC_TID(_currentConnId, eAntennaNo._1, eReadType.Single, count, mc, match, 0, pwd);
                }
                else if (bank == 3) // User
                {
                    ret = RFIDReader._Tag6C.GetEPC_UserData(_currentConnId, eAntennaNo._1, eReadType.Single, offset, count, mc, match, 0, pwd);
                }
                else // Reserved
                {
                    ret = RFIDReader._Tag6C.GetEPC_ReservedData(_currentConnId, eAntennaNo._1, eReadType.Single, offset, count, mc, match, 0, pwd);
                }

                Dictionary<string, object> res = new Dictionary<string, object>();
                res["type"] = "read_bank_result";
                res["success"] = ret == 0;
                res["retCode"] = ret;
                BroadcastJson(res);
            }
            catch (Exception ex)
            {
                BroadcastLog("Read Bank Exception: " + ex.Message);
            }
        }

        private static void HandleWriteBank(Dictionary<string, object> obj)
        {
            if (!_isConnected) return;
            try
            {
                int bank = Convert.ToInt32(obj["bank"]);
                int offset = Convert.ToInt32(obj["offset"]);
                string hexData = obj["data"].ToString();
                string match = obj.ContainsKey("match") ? obj["match"].ToString() : "";
                string pwd = obj.ContainsKey("pwd") ? obj["pwd"].ToString() : "00000000";

                eMatchCode mc = !string.IsNullOrEmpty(match) ? eMatchCode.EPC : eMatchCode.None;
                string result = "";

                if (bank == 1) // EPC
                {
                    result = RFIDReader._Tag6C.WriteEPC(_currentConnId, eAntennaNo._1, hexData, offset.ToString(), mc, match, 0, pwd);
                }
                else if (bank == 3) // User
                {
                    result = RFIDReader._Tag6C.WriteUserData(_currentConnId, eAntennaNo._1, hexData, offset, mc, match, 0, pwd);
                }
                else if (bank == 0) // Reserved
                {
                    if (offset == 0)
                        result = RFIDReader._Tag6C.WriteDestroyPassWord(_currentConnId, eAntennaNo._1, hexData, mc, match, 0, pwd);
                    else
                        result = RFIDReader._Tag6C.WriteAccessPassWord(_currentConnId, eAntennaNo._1, hexData, mc, match, 0, pwd);
                }

                Dictionary<string, object> res = new Dictionary<string, object>();
                res["type"] = "write_bank_result";
                res["success"] = result == "0";
                res["result"] = result;
                BroadcastJson(res);
            }
            catch (Exception ex)
            {
                BroadcastLog("Write Bank Exception: " + ex.Message);
            }
        }

        private static void HandleFastWriteEpc(Dictionary<string, object> obj)
        {
            if (!_isConnected) return;
            try
            {
                string newEpc = obj["epc"].ToString();
                string oldEpc = obj.ContainsKey("old_epc") ? obj["old_epc"].ToString() : "";
                string pwd = "00000000";

                eMatchCode mc = !string.IsNullOrEmpty(oldEpc) ? eMatchCode.EPC : eMatchCode.None;
                string ret = RFIDReader._Tag6C.WriteEPC(_currentConnId, eAntennaNo._1, newEpc, "2", mc, oldEpc, 0, pwd);

                Dictionary<string, object> res = new Dictionary<string, object>();
                res["type"] = "fast_write_result";
                res["success"] = ret == "0";
                res["result"] = ret;
                BroadcastJson(res);
            }
            catch (Exception ex)
            {
                BroadcastLog("Fast Write EPC Exception: " + ex.Message);
            }
        }

        private static void HandleLock(Dictionary<string, object> obj)
        {
            if (!_isConnected) return;
            try
            {
                int area = Convert.ToInt32(obj["area"]);
                int lockType = Convert.ToInt32(obj["type"]);
                string pwd = obj.ContainsKey("pwd") ? obj["pwd"].ToString() : "00000000";
                string match = obj.ContainsKey("match") ? obj["match"].ToString() : "";

                int ret = -1;
                if (!string.IsNullOrEmpty(match))
                {
                    ret = RFIDReader._Tag6C.Lock_MatchEPC(_currentConnId, eAntennaNo._1, (eLockArea)area, (eLockType)lockType, match, 0, pwd);
                }
                else
                {
                    ret = RFIDReader._Tag6C.Lock(_currentConnId, eAntennaNo._1, (eLockArea)area, (eLockType)lockType);
                }

                Dictionary<string, object> res = new Dictionary<string, object>();
                res["type"] = "lock_result";
                res["success"] = ret == 0;
                res["retCode"] = ret;
                BroadcastJson(res);
            }
            catch (Exception ex)
            {
                BroadcastLog("Lock Tag Exception: " + ex.Message);
            }
        }

        private static void HandleKill(Dictionary<string, object> obj)
        {
            if (!_isConnected) return;
            try
            {
                string pwd = obj.ContainsKey("pwd") ? obj["pwd"].ToString() : "00000000";
                string match = obj.ContainsKey("match") ? obj["match"].ToString() : "";

                int ret = -1;
                if (!string.IsNullOrEmpty(match))
                {
                    ret = RFIDReader._Tag6C.Destroy_MatchEPC(_currentConnId, eAntennaNo._1, pwd, match, 0);
                }
                else
                {
                    ret = RFIDReader._Tag6C.Destroy(_currentConnId, eAntennaNo._1, pwd);
                }

                Dictionary<string, object> res = new Dictionary<string, object>();
                res["type"] = "kill_result";
                res["success"] = ret == 0;
                res["retCode"] = ret;
                BroadcastJson(res);
            }
            catch (Exception ex)
            {
                BroadcastLog("Kill Tag Exception: " + ex.Message);
            }
        }

        private static void HandleSetGpo(Dictionary<string, object> obj)
        {
            if (!_isConnected) return;
            try
            {
                int index = Convert.ToInt32(obj["index"]);
                bool state = Convert.ToBoolean(obj["state"]);
                Dictionary<eGPO, eGPOState> gpoDic = new Dictionary<eGPO, eGPOState>();
                eGPO gpo = index == 1 ? eGPO._1 : (index == 2 ? eGPO._2 : (index == 3 ? eGPO._3 : eGPO._4));
                gpoDic[gpo] = state ? eGPOState.High : eGPOState.Low;
                int ret = RFIDReader._ReaderConfig.SetReaderGPOState(_currentConnId, gpoDic);
                BroadcastLog(string.Format("Set GPO {0} -> {1} (Result: {2})", index, state ? "HIGH" : "LOW", ret));
            }
            catch (Exception ex)
            {
                BroadcastLog("Set GPO Exception: " + ex.Message);
            }
        }

        public static void BroadcastLog(string msg)
        {
            Console.WriteLine(string.Format("[{0:HH:mm:ss}] {1}", DateTime.Now, msg));
            Dictionary<string, object> logObj = new Dictionary<string, object>();
            logObj["type"] = "log";
            logObj["msg"] = msg;
            BroadcastJson(logObj);
        }

        public static void BroadcastJson(object data)
        {
            string json = _json.Serialize(data) + "\n";
            byte[] bytes = Encoding.UTF8.GetBytes(json);

            lock (_clientLock)
            {
                for (int i = _clients.Count - 1; i >= 0; i--)
                {
                    try
                    {
                        if (_clients[i].Connected)
                        {
                            _clients[i].GetStream().Write(bytes, 0, bytes.Length);
                        }
                        else
                        {
                            _clients.RemoveAt(i);
                        }
                    }
                    catch
                    {
                        _clients.RemoveAt(i);
                    }
                }
            }
        }

        #region IAsynchronousMessage Implementation

        public void OutPutTags(Tag_Model tag)
        {
            if (tag == null) return;

            string antNum = tag.ANT_NUM > 0 ? tag.ANT_NUM.ToString() : "1";

            Dictionary<string, object> tagObj = new Dictionary<string, object>();
            tagObj["type"] = "tag";
            tagObj["epc"] = tag.EPC ?? "";
            tagObj["tid"] = tag.TID ?? "";
            tagObj["user"] = tag.UserData ?? "";
            tagObj["rssi"] = tag.RSSI.ToString();
            tagObj["ant"] = antNum;
            tagObj["count"] = tag.TotalCount > 0 ? tag.TotalCount : 1;
            tagObj["freq"] = tag.Frequency.ToString();
            tagObj["phase"] = tag.Phase.ToString();

            BroadcastJson(tagObj);
        }

        public void OutPutTagsOver()
        {
        }

        public void WriteDebugMsg(string msg)
        {
            BroadcastLog("DEBUG: " + msg);
        }

        public void WriteLog(string msg)
        {
            BroadcastLog("INFO: " + msg);
        }

        public void PortConnecting(string connID)
        {
            BroadcastLog("Port Connecting: " + connID);
            _currentConnId = connID;
            _isConnected = true;

            Dictionary<string, object> res = new Dictionary<string, object>();
            res["type"] = "status";
            res["connected"] = true;
            res["connId"] = connID;
            BroadcastJson(res);
        }

        public void PortClosing(string connID)
        {
            BroadcastLog("Port Closing: " + connID);
            _isConnected = false;
            _isScanning = false;
            _currentConnId = "";

            Dictionary<string, object> res = new Dictionary<string, object>();
            res["type"] = "status";
            res["connected"] = false;
            res["scanning"] = false;
            res["connId"] = "";
            BroadcastJson(res);
        }

        public void GPIControlMsg(GPI_Model gpi_model)
        {
            if (gpi_model != null)
            {
                Dictionary<string, object> res = new Dictionary<string, object>();
                res["type"] = "gpi";
                res["index"] = gpi_model.GpiIndex;
                res["state"] = gpi_model.GpiState;
                BroadcastJson(res);

                BroadcastLog(string.Format("GPI Event: Port {0} is {1}", gpi_model.GpiIndex, gpi_model.GpiState == 1 ? "HIGH" : "LOW"));
            }
        }

        public void EventUpload(CallBackEnum type, object param)
        {
            BroadcastLog("Reader Event: " + type + " -> " + param);
        }

        public void OutPutBarCode(string code)
        {
            BroadcastLog("Barcode: " + code);
        }

        #endregion

        #region ISearchDevice Implementation

        public void DeviceInfo(Device_Model model)
        {
            if (model != null)
            {
                Dictionary<string, object> res = new Dictionary<string, object>();
                res["type"] = "discovered_device";
                res["ip"] = model.IP ?? "";
                res["mac"] = model.MAC ?? "";
                res["mask"] = model.Mask ?? "";
                res["gateway"] = model.Gateway ?? "";
                res["port"] = model.ServerPort ?? "9090";
                res["mode"] = model.WorkingMode ?? "";
                res["deviceType"] = model.DeviceType ?? "HF340 / CL7206";
                BroadcastJson(res);

                BroadcastLog(string.Format("Discovered LAN Reader: IP {0}, MAC {1}", model.IP, model.MAC));
            }
        }

        public void DebugMsg(string msg)
        {
            BroadcastLog("Search Debug: " + msg);
        }

        #endregion
    }
}
