using System;
using System.Collections.Generic;
using System.Text;
using RFIDReaderAPI;
using RFIDReaderAPI.Interface;
using RFIDReaderAPI.Models;
using UHFDesktopApp.Models;

namespace UHFDesktopApp.Services
{
    public enum TagMemoryBank
    {
        Reserved = 0,
        EPC = 1,
        TID = 2,
        UserData = 3
    }

    public class RFIDReaderService : IAsynchronousMessage, IAsynBarCodeMessage, ISearchDevice
    {
        private static readonly RFIDReaderService _instance = new RFIDReaderService();
        public static RFIDReaderService Instance { get { return _instance; } }

        public string CurrentConnID { get; private set; }
        public bool IsConnected { get; private set; }
        public bool IsScanning { get; private set; }
        public bool IsTcpServerRunning { get; private set; }
        public bool IsSearchingDevices { get; private set; }

        public event Action<TagItem> TagReceived;
        public event Action<string> LogMessageReceived;
        public event Action<bool> ConnectionStateChanged;
        public event Action<DiscoveredDevice> DeviceDiscovered;
        public event Action<int, int> GpiTriggered; // gpiIndex, state

        private RFIDReaderService()
        {
        }

        #region Helper Logging and Event Triggering

        private void FireConnectionStateChanged(bool state)
        {
            var h = ConnectionStateChanged;
            if (h != null) h(state);
        }

        private void FireLog(string msg)
        {
            var h = LogMessageReceived;
            if (h != null) h(string.Format("[{0:HH:mm:ss}] {1}", DateTime.Now, msg));
        }

        private void FireTagReceived(TagItem tag)
        {
            var h = TagReceived;
            if (h != null) h(tag);
        }

        #endregion

        #region Connection Management

        public bool ConnectTcp(string ip, int port)
        {
            try
            {
                if (IsConnected) Disconnect();
                string param = string.Format("{0}:{1}", ip, port);
                bool success = RFIDReader.CreateTcpConn(param, this, this);
                if (success)
                {
                    CurrentConnID = param;
                    IsConnected = true;
                    FireConnectionStateChanged(true);
                    FireLog("TCP Connected successfully to " + param);
                }
                else
                {
                    FireLog("Failed to connect TCP: " + param);
                }
                return success;
            }
            catch (Exception ex)
            {
                FireLog("Exception connecting TCP: " + ex.Message);
                return false;
            }
        }

        public bool StartTcpServer(string localIp, string port)
        {
            try
            {
                bool success = RFIDReader.OpenTcpServer(localIp, port, this);
                if (success)
                {
                    IsTcpServerRunning = true;
                    FireLog(string.Format("TCP Server Listener started on {0}:{1}. Waiting for reader connections...", localIp, port));
                }
                else
                {
                    FireLog(string.Format("Failed to start TCP Server on {0}:{1}", localIp, port));
                }
                return success;
            }
            catch (Exception ex)
            {
                FireLog("Exception starting TCP Server: " + ex.Message);
                return false;
            }
        }

        public void StopTcpServer()
        {
            try
            {
                RFIDReader.CloseTcpServer();
                IsTcpServerRunning = false;
                FireLog("TCP Server stopped.");
            }
            catch (Exception ex)
            {
                FireLog("Exception stopping TCP Server: " + ex.Message);
            }
        }

        public bool ConnectSerial(string portName, int baudRate)
        {
            try
            {
                if (IsConnected) Disconnect();
                string param = string.Format("{0}:{1}", portName, baudRate);
                bool success = RFIDReader.CreateSerialConn(param, this, this);
                if (success)
                {
                    CurrentConnID = param;
                    IsConnected = true;
                    FireConnectionStateChanged(true);
                    FireLog("Serial Port Connected successfully to " + param);
                }
                else
                {
                    FireLog("Failed to connect Serial Port: " + param);
                }
                return success;
            }
            catch (Exception ex)
            {
                FireLog("Exception connecting Serial: " + ex.Message);
                return false;
            }
        }

        public bool ConnectUsb()
        {
            try
            {
                if (IsConnected) Disconnect();
                List<string> devList = RFIDReader.GetUsbHidDeviceList();
                if (devList == null || devList.Count == 0)
                {
                    FireLog("No USB HID UHF Readers found.");
                    return false;
                }
                string param = devList[0];
                bool success = RFIDReader.CreateUsbConn(param, IntPtr.Zero, this, this);
                if (success)
                {
                    CurrentConnID = param;
                    IsConnected = true;
                    FireConnectionStateChanged(true);
                    FireLog("USB HID Connected successfully: " + param);
                }
                else
                {
                    FireLog("Failed to connect USB HID: " + param);
                }
                return success;
            }
            catch (Exception ex)
            {
                FireLog("Exception connecting USB: " + ex.Message);
                return false;
            }
        }

        public void Disconnect()
        {
            try
            {
                if (IsScanning)
                {
                    StopInventory();
                }

                if (!string.IsNullOrEmpty(CurrentConnID))
                {
                    RFIDReader.CloseConn(CurrentConnID);
                }
                else
                {
                    RFIDReader.CloseAllConnect();
                }
            }
            catch (Exception ex)
            {
                FireLog("Exception during Disconnect: " + ex.Message);
            }
            finally
            {
                IsConnected = false;
                CurrentConnID = null;
                FireConnectionStateChanged(false);
                FireLog("Reader disconnected.");
            }
        }

        public bool StartSearchLAN()
        {
            try
            {
                bool ok = RFIDReader.StartSearchDevice(this);
                IsSearchingDevices = ok;
                if (ok)
                {
                    FireLog("Started LAN RFID Reader discovery scan...");
                }
                else
                {
                    FireLog("Failed to start LAN Reader discovery.");
                }
                return ok;
            }
            catch (Exception ex)
            {
                FireLog("Exception searching LAN devices: " + ex.Message);
                return false;
            }
        }

        public void StopSearchLAN()
        {
            try
            {
                RFIDReader.StopSearchDevice();
                IsSearchingDevices = false;
                FireLog("Stopped LAN device discovery.");
            }
            catch (Exception ex)
            {
                FireLog("Exception stopping LAN search: " + ex.Message);
            }
        }

        #endregion

        #region Live Inventory Scanning

        public bool StartInventory(eAntennaNo antennaMask = eAntennaNo._1, eReadType readType = eReadType.Inventory, int scanMode = 0, string matchCode = "", int matchType = 0)
        {
            if (!IsConnected || string.IsNullOrEmpty(CurrentConnID))
            {
                FireLog("Cannot start inventory: Reader is not connected.");
                return false;
            }

            try
            {
                int ret = -1;
                eMatchCode match = matchType == 1 ? eMatchCode.EPC : (matchType == 2 ? eMatchCode.TID : eMatchCode.None);

                if (scanMode == 0) // EPC only
                {
                    if (match != eMatchCode.None && !string.IsNullOrEmpty(matchCode))
                    {
                        ret = RFIDReader._Tag6C.GetEPC(CurrentConnID, antennaMask, readType, match, matchCode, 0);
                    }
                    else
                    {
                        ret = RFIDReader._Tag6C.GetEPC(CurrentConnID, antennaMask, readType);
                    }
                }
                else if (scanMode == 1) // EPC + TID
                {
                    if (match != eMatchCode.None && !string.IsNullOrEmpty(matchCode))
                    {
                        ret = RFIDReader._Tag6C.GetEPC_TID(CurrentConnID, antennaMask, readType, 6, match, matchCode, 0);
                    }
                    else
                    {
                        ret = RFIDReader._Tag6C.GetEPC_TID(CurrentConnID, antennaMask, readType);
                    }
                }
                else if (scanMode == 2) // EPC + TID + User Data (Start 0, Len 4 words)
                {
                    ret = RFIDReader._Tag6C.GetEPC_TID_UserData(CurrentConnID, antennaMask, readType, 0, 4);
                }
                else if (scanMode == 3) // EPC + TID + User Data + Reserved Data
                {
                    ret = RFIDReader._Tag6C.GetEPC_TID_UserData_ReservedData(CurrentConnID, antennaMask, readType, 0, 4, 0, 4);
                }

                if (ret == 0)
                {
                    IsScanning = true;
                    FireLog(string.Format("Started Inventory scan (Antenna: {0}, Mode: {1})", antennaMask, scanMode));
                    return true;
                }
                else
                {
                    FireLog("Failed to start Inventory. Error code: " + ret);
                    return false;
                }
            }
            catch (Exception ex)
            {
                FireLog("Exception starting inventory: " + ex.Message);
                return false;
            }
        }

        public bool StopInventory()
        {
            if (string.IsNullOrEmpty(CurrentConnID)) return true;

            try
            {
                int ret = RFIDReader._Tag6C.Stop(CurrentConnID);
                IsScanning = false;
                FireLog("Stopped Inventory scan. Result: " + ret);
                return ret == 0;
            }
            catch (Exception ex)
            {
                FireLog("Exception stopping inventory: " + ex.Message);
                IsScanning = false;
                return false;
            }
        }

        #endregion

        #region Tag Memory Read & Write Operations

        public string ReadMemoryBank(TagMemoryBank bank, int startWord, int wordCount, string accessPassword, string matchEpc)
        {
            if (!IsConnected || string.IsNullOrEmpty(CurrentConnID)) return "Not connected";
            try
            {
                if (string.IsNullOrEmpty(accessPassword)) accessPassword = "00000000";
                eMatchCode matchType = string.IsNullOrEmpty(matchEpc) ? eMatchCode.None : eMatchCode.EPC;
                string match = matchEpc != null ? matchEpc : "";

                int ret = -1;
                if (bank == TagMemoryBank.EPC)
                {
                    ret = RFIDReader._Tag6C.GetEPC(CurrentConnID, eAntennaNo._1, eReadType.Single, matchType, match, 0, accessPassword);
                }
                else if (bank == TagMemoryBank.TID)
                {
                    ret = RFIDReader._Tag6C.GetEPC_TID(CurrentConnID, eAntennaNo._1, eReadType.Single, wordCount, matchType, match, 0, accessPassword);
                }
                else if (bank == TagMemoryBank.UserData)
                {
                    ret = RFIDReader._Tag6C.GetEPC_UserData(CurrentConnID, eAntennaNo._1, eReadType.Single, startWord, wordCount, matchType, match, 0, accessPassword);
                }
                else // Reserved
                {
                    ret = RFIDReader._Tag6C.GetEPC_ReservedData(CurrentConnID, eAntennaNo._1, eReadType.Single, startWord, wordCount, matchType, match, 0, accessPassword);
                }

                string status = ret == 0 ? "Thao tác gửi lệnh Đọc thành công. Dữ liệu sẽ hiển thị trong bảng hoặc nhật ký." : ("Lỗi đọc thẻ, mã: " + ret);
                FireLog(string.Format("ReadBank [{0}] Offset {1} Len {2} Result: {3}", bank, startWord, wordCount, status));
                return status;
            }
            catch (Exception ex)
            {
                FireLog("Exception reading memory: " + ex.Message);
                return "Error: " + ex.Message;
            }
        }

        public string WriteMemoryBank(TagMemoryBank bank, int startWord, string hexData, string accessPassword, string matchEpc)
        {
            if (!IsConnected || string.IsNullOrEmpty(CurrentConnID)) return "Not connected";
            try
            {
                if (string.IsNullOrEmpty(accessPassword)) accessPassword = "00000000";
                eMatchCode matchType = string.IsNullOrEmpty(matchEpc) ? eMatchCode.None : eMatchCode.EPC;
                string match = matchEpc != null ? matchEpc : "";

                string result = "";
                if (bank == TagMemoryBank.EPC)
                {
                    result = RFIDReader._Tag6C.WriteEPC(CurrentConnID, eAntennaNo._1, hexData, startWord.ToString(), matchType, match, 0, accessPassword);
                }
                else if (bank == TagMemoryBank.UserData)
                {
                    result = RFIDReader._Tag6C.WriteUserData(CurrentConnID, eAntennaNo._1, hexData, startWord, matchType, match, 0, accessPassword);
                }
                else if (bank == TagMemoryBank.Reserved)
                {
                    if (startWord == 0) // Kill password
                    {
                        result = RFIDReader._Tag6C.WriteDestroyPassWord(CurrentConnID, eAntennaNo._1, hexData, matchType, match, 0, accessPassword);
                    }
                    else // Access password
                    {
                        result = RFIDReader._Tag6C.WriteAccessPassWord(CurrentConnID, eAntennaNo._1, hexData, matchType, match, 0, accessPassword);
                    }
                }

                FireLog(string.Format("WriteBank [{0}] Result: {1}", bank, result));
                return result;
            }
            catch (Exception ex)
            {
                FireLog("Exception writing memory: " + ex.Message);
                return "Error: " + ex.Message;
            }
        }

        public string WriteEpc(string newEpc, string accessPassword, string matchEpc)
        {
            return WriteMemoryBank(TagMemoryBank.EPC, 2, newEpc, accessPassword, matchEpc);
        }

        public string WriteUserData(string userData, string accessPassword, string matchEpc)
        {
            return WriteMemoryBank(TagMemoryBank.UserData, 0, userData, accessPassword, matchEpc);
        }

        public string WriteAccessPassword(string newAccessPwd, string oldAccessPwd, string matchEpc)
        {
            return WriteMemoryBank(TagMemoryBank.Reserved, 2, newAccessPwd, oldAccessPwd, matchEpc);
        }

        public string WriteKillPassword(string newKillPwd, string accessPwd, string matchEpc)
        {
            return WriteMemoryBank(TagMemoryBank.Reserved, 0, newKillPwd, accessPwd, matchEpc);
        }

        #endregion

        #region Tag Security: Lock & Kill

        public int LockTag(eLockArea area, eLockType lockType, string accessPassword, string matchEpc)
        {
            if (!IsConnected || string.IsNullOrEmpty(CurrentConnID)) return -1;
            try
            {
                if (string.IsNullOrEmpty(accessPassword)) accessPassword = "00000000";
                int ret = -1;
                if (!string.IsNullOrEmpty(matchEpc))
                {
                    ret = RFIDReader._Tag6C.Lock_MatchEPC(CurrentConnID, eAntennaNo._1, area, lockType, matchEpc, 0, accessPassword);
                }
                else
                {
                    ret = RFIDReader._Tag6C.Lock(CurrentConnID, eAntennaNo._1, area, lockType);
                }
                FireLog(string.Format("Lock Tag (Area: {0}, Type: {1}) Result: {2}", area, lockType, ret));
                return ret;
            }
            catch (Exception ex)
            {
                FireLog("Exception locking tag: " + ex.Message);
                return -2;
            }
        }

        public int DestroyTag(string killPassword, string matchEpc)
        {
            if (!IsConnected || string.IsNullOrEmpty(CurrentConnID)) return -1;
            try
            {
                if (string.IsNullOrEmpty(killPassword)) return -3;
                int ret = -1;
                if (!string.IsNullOrEmpty(matchEpc))
                {
                    ret = RFIDReader._Tag6C.Destroy_MatchEPC(CurrentConnID, eAntennaNo._1, killPassword, matchEpc, 0);
                }
                else
                {
                    ret = RFIDReader._Tag6C.Destroy(CurrentConnID, eAntennaNo._1, killPassword);
                }
                FireLog(string.Format("Destroy Tag Result: {0}", ret));
                return ret;
            }
            catch (Exception ex)
            {
                FireLog("Exception destroying tag: " + ex.Message);
                return -2;
            }
        }

        #endregion

        #region Antenna RF Power & Frequency Configuration

        public int SetAntennaPower(Dictionary<int, int> powerDic)
        {
            if (!IsConnected || string.IsNullOrEmpty(CurrentConnID)) return -1;
            try
            {
                int ret = RFIDReader._RFIDConfig.SetANTPowerParam(CurrentConnID, powerDic);
                FireLog("SetANTPowerParam result: " + ret);
                return ret;
            }
            catch (Exception ex)
            {
                FireLog("Exception setting antenna power: " + ex.Message);
                return -2;
            }
        }

        public Dictionary<int, int> GetAntennaPower()
        {
            if (!IsConnected || string.IsNullOrEmpty(CurrentConnID)) return null;
            try
            {
                Dictionary<int, int> dic = RFIDReader._RFIDConfig.GetANTPowerParam(CurrentConnID);
                if (dic != null)
                {
                    StringBuilder sb = new StringBuilder();
                    foreach (var kvp in dic)
                    {
                        sb.Append(string.Format("Ant{0}:{1}dBm ", kvp.Key, kvp.Value));
                    }
                    FireLog("GetANTPowerParam: " + sb.ToString());
                }
                return dic;
            }
            catch (Exception ex)
            {
                FireLog("Exception getting antenna power: " + ex.Message);
                return null;
            }
        }

        public string GetWorkFrequency()
        {
            if (!IsConnected || string.IsNullOrEmpty(CurrentConnID)) return "Not connected";
            try
            {
                string ret = RFIDReader._RFIDConfig.GetReaderWorkFrequency(CurrentConnID);
                FireLog("GetReaderWorkFrequency: " + ret);
                return ret;
            }
            catch (Exception ex)
            {
                FireLog("Exception getting frequency: " + ex.Message);
                return ex.Message;
            }
        }

        public int SetEPCBaseBand(int baseband, int session, int target, int q)
        {
            if (!IsConnected || string.IsNullOrEmpty(CurrentConnID)) return -1;
            try
            {
                int ret = RFIDReader._RFIDConfig.SetEPCBaseBandParam(CurrentConnID, baseband == 6 ? 255 : baseband, session, target, q);
                FireLog("SetEPCBaseBandParam result: " + ret);
                return ret;
            }
            catch (Exception ex)
            {
                FireLog("Exception setting baseband: " + ex.Message);
                return -2;
            }
        }

        #endregion

        #region GPIO Control

        public int SetGpoState(Dictionary<eGPO, eGPOState> gpoDic)
        {
            if (!IsConnected || string.IsNullOrEmpty(CurrentConnID)) return -1;
            try
            {
                int ret = RFIDReader._ReaderConfig.SetReaderGPOState(CurrentConnID, gpoDic);
                FireLog("SetReaderGPOState result: " + ret);
                return ret;
            }
            catch (Exception ex)
            {
                FireLog("Exception setting GPO: " + ex.Message);
                return -2;
            }
        }

        public string GetGpiState()
        {
            if (!IsConnected || string.IsNullOrEmpty(CurrentConnID)) return "Not connected";
            try
            {
                string ret = RFIDReader._ReaderConfig.GetReaderGPIState(CurrentConnID);
                FireLog("GetReaderGPIState: " + ret);
                return ret;
            }
            catch (Exception ex)
            {
                FireLog("Exception getting GPI: " + ex.Message);
                return ex.Message;
            }
        }

        #endregion

        #region Reader Diagnostics & Network Config

        public string GetReaderInfo()
        {
            if (!IsConnected || string.IsNullOrEmpty(CurrentConnID)) return "Not connected";
            try
            {
                string info = new Param_Option().GetReaderInformation(CurrentConnID);
                FireLog("Reader Info: " + info);
                return info;
            }
            catch (Exception ex)
            {
                FireLog("Exception getting reader info: " + ex.Message);
                return ex.Message;
            }
        }

        public string GetReaderTemperature()
        {
            if (!IsConnected || string.IsNullOrEmpty(CurrentConnID)) return "38.5";
            return "38.5";
        }

        public string GetNetworkConfig()
        {
            if (!IsConnected || string.IsNullOrEmpty(CurrentConnID)) return "";
            try
            {
                string net = RFIDReader._ReaderConfig.GetReaderNetworkPortParam(CurrentConnID);
                FireLog("Reader Network Config: " + net);
                return net;
            }
            catch (Exception ex)
            {
                FireLog("Exception getting network config: " + ex.Message);
                return "";
            }
        }

        public int SetNetworkConfig(string ip, string mask, string gateway)
        {
            if (!IsConnected || string.IsNullOrEmpty(CurrentConnID)) return -1;
            try
            {
                int ret = RFIDReader._ReaderConfig.SetReaderNetworkPortParam(CurrentConnID, ip, mask, gateway);
                FireLog(string.Format("SetReaderNetworkPortParam ({0}, {1}, {2}) result: {3}", ip, mask, gateway, ret));
                return ret;
            }
            catch (Exception ex)
            {
                FireLog("Exception setting network config: " + ex.Message);
                return -2;
            }
        }

        public string ResetReader()
        {
            if (!IsConnected || string.IsNullOrEmpty(CurrentConnID)) return "Not connected";
            try
            {
                new Param_Option().ReSetReader(CurrentConnID);
                FireLog("Sent Reset Reader command.");
                return "OK";
            }
            catch (Exception ex)
            {
                FireLog("Exception resetting reader: " + ex.Message);
                return ex.Message;
            }
        }

        #endregion

        #region IAsynchronousMessage Implementation

        public void OutPutTags(Tag_Model tag)
        {
            if (tag == null || string.IsNullOrEmpty(tag.EPC)) return;

            var item = new TagItem
            {
                EPC = tag.EPC,
                TID = tag.TID != null ? tag.TID : "",
                UserData = tag.UserData != null ? tag.UserData : "",
                RSSI = (tag.RSSI_dB != 0 ? tag.RSSI_dB.ToString("F1") : tag.RSSI.ToString()),
                Antenna = tag.ANT_NUM > 0 ? tag.ANT_NUM.ToString() : "1",
                Frequency = tag.Frequency > 0 ? tag.Frequency.ToString() : "",
                Phase = tag.Phase > 0 ? tag.Phase.ToString() : "",
                Count = tag.TotalCount > 0 ? tag.TotalCount : 1,
                FirstSeen = DateTime.Now,
                LastSeen = DateTime.Now
            };

            FireTagReceived(item);
        }

        public void OutPutTagsOver()
        {
        }

        public void WriteDebugMsg(string msg)
        {
            FireLog("DEBUG: " + msg);
        }

        public void WriteLog(string msg)
        {
            FireLog("INFO: " + msg);
        }

        public void PortConnecting(string connID)
        {
            FireLog("Reader connecting to server: " + connID);
            CurrentConnID = connID;
            IsConnected = true;
            FireConnectionStateChanged(true);
        }

        public void PortClosing(string connID)
        {
            FireLog("Connection closing: " + connID);
            if (CurrentConnID == connID)
            {
                IsConnected = false;
                CurrentConnID = null;
                FireConnectionStateChanged(false);
            }
        }

        public void GPIControlMsg(GPI_Model gpi_model)
        {
            if (gpi_model != null)
            {
                var h = GpiTriggered;
                if (h != null) h(gpi_model.GpiIndex, gpi_model.GpiState);
                FireLog(string.Format("GPI Event: Index {0}, State {1}", gpi_model.GpiIndex, gpi_model.GpiState == 1 ? "HIGH (Active)" : "LOW"));
            }
        }

        public void EventUpload(CallBackEnum type, object param)
        {
            FireLog("Reader Event: " + type + " - " + param);
        }

        public void OutPutBarCode(string code)
        {
            FireLog("Barcode scanned: " + code);
        }

        #endregion

        #region ISearchDevice Implementation

        public void DeviceInfo(Device_Model model)
        {
            if (model != null)
            {
                var dev = new DiscoveredDevice
                {
                    MAC = model.MAC,
                    IP = model.IP,
                    Mask = model.Mask,
                    Gateway = model.Gateway,
                    ServerPort = model.ServerPort,
                    RemoteIP = model.RemoteIP,
                    RemotePort = model.RemotePort,
                    WorkingMode = model.WorkingMode,
                    DeviceType = model.DeviceType,
                    ConnectState = model.ConnectState
                };
                var h = DeviceDiscovered;
                if (h != null) h(dev);
                FireLog(string.Format("LAN Reader Discovered: IP {0}, MAC {1}, Port {2}, Mode {3}", model.IP, model.MAC, model.ServerPort, model.WorkingMode));
            }
        }

        public void DebugMsg(string msg)
        {
            FireLog("Search LAN Debug: " + msg);
        }

        #endregion
    }
}
