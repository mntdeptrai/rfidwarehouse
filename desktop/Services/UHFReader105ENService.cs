using System;
using System.Collections.Generic;
using System.Text;
using System.Threading;
using ReaderB;
using UHFDesktopApp.Models;

namespace UHFDesktopApp.Services
{
    public class UHFReader105ENService
    {
        private static readonly UHFReader105ENService _instance = new UHFReader105ENService();
        public static UHFReader105ENService Instance { get { return _instance; } }

        public int PortHandle { get; private set; }
        public int ComPort { get; private set; }
        public byte ComAddr { get; set; }
        public bool IsConnected { get; private set; }
        public bool IsScanning { get; private set; }

        public event Action<TagItem> TagReceived;
        public event Action<string> LogMessageReceived;
        public event Action<bool> ConnectionStateChanged;

        private Thread _scanThread;

        private UHFReader105ENService()
        {
            PortHandle = -1;
            ComPort = -1;
            ComAddr = 0xFF;
        }

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

        public bool AutoConnect()
        {
            try
            {
                int port = 0;
                byte baud = 5; // 57600
                int handle = 0;
                byte addr = 0xFF;

                int ret = StaticClassReaderB.AutoOpenComPort(ref port, ref addr, baud, ref handle);
                if (ret == 0)
                {
                    PortHandle = handle;
                    ComPort = port;
                    ComAddr = addr;
                    IsConnected = true;
                    FireConnectionStateChanged(true);
                    FireLog(string.Format("Auto-connected 105EN Reader on COM{0}, Addr=0x{1:X2}", port, addr));
                    return true;
                }
                else
                {
                    FireLog("AutoOpenComPort failed. Return code: " + ret);
                    return false;
                }
            }
            catch (Exception ex)
            {
                FireLog("Exception during 105EN AutoConnect: " + ex.Message);
                return false;
            }
        }

        public bool Connect(int port, byte baud)
        {
            try
            {
                int handle = 0;
                byte addr = ComAddr;

                int ret = StaticClassReaderB.OpenComPort(port, ref addr, baud, ref handle);
                if (ret == 0)
                {
                    PortHandle = handle;
                    ComPort = port;
                    ComAddr = addr;
                    IsConnected = true;
                    FireConnectionStateChanged(true);
                    FireLog(string.Format("Connected 105EN Reader on COM{0}", port));
                    return true;
                }
                else
                {
                    FireLog(string.Format("Failed to open COM{0}. Code: {1}", port, ret));
                    return false;
                }
            }
            catch (Exception ex)
            {
                FireLog("Exception connecting COM: " + ex.Message);
                return false;
            }
        }

        public void Disconnect()
        {
            try
            {
                StopInventory();
                if (PortHandle != -1 || ComPort != -1)
                {
                    if (ComPort != -1)
                    {
                        StaticClassReaderB.CloseSpecComPort(ComPort);
                    }
                    else
                    {
                        StaticClassReaderB.CloseComPort();
                    }
                }
            }
            catch (Exception ex)
            {
                FireLog("Exception disconnecting 105EN: " + ex.Message);
            }
            finally
            {
                PortHandle = -1;
                ComPort = -1;
                IsConnected = false;
                FireConnectionStateChanged(false);
                FireLog("105EN Reader Disconnected.");
            }
        }

        public bool StartInventory()
        {
            if (!IsConnected) return false;
            if (IsScanning) return true;

            IsScanning = true;
            _scanThread = new Thread(ScanLoop)
            {
                IsBackground = true
            };
            _scanThread.Start();
            FireLog("Started 105EN Inventory scan loop.");
            return true;
        }

        public void StopInventory()
        {
            IsScanning = false;
            if (_scanThread != null)
            {
                try
                {
                    _scanThread.Join(500);
                }
                catch { }
                _scanThread = null;
            }
            FireLog("Stopped 105EN Inventory.");
        }

        private void ScanLoop()
        {
            byte[] epcBuffer = new byte[5000];
            int totalLen = 0;
            int cardNum = 0;

            while (IsScanning && IsConnected)
            {
                try
                {
                    byte addr = ComAddr;
                    int ret = StaticClassReaderB.Inventory_G2(ref addr, 0, 0, 0, epcBuffer, ref totalLen, ref cardNum, PortHandle);
                    if (ret == 1 || ret == 2 || ret == 3 || ret == 4 || (ret == 0 && cardNum > 0))
                    {
                        if (cardNum > 0 && totalLen > 0)
                        {
                            int ptr = 0;
                            for (int i = 0; i < cardNum; i++)
                            {
                                if (ptr >= totalLen) break;
                                int epcLen = epcBuffer[ptr++];
                                if (epcLen <= 0 || ptr + epcLen > totalLen) break;

                                StringBuilder sb = new StringBuilder(epcLen * 2);
                                for (int k = 0; k < epcLen; k++)
                                {
                                    sb.AppendFormat("{0:X2}", epcBuffer[ptr + k]);
                                }
                                ptr += epcLen;

                                string epcStr = sb.ToString();
                                if (!string.IsNullOrEmpty(epcStr))
                                {
                                    var item = new TagItem
                                    {
                                        EPC = epcStr,
                                        TID = "",
                                        UserData = "",
                                        RSSI = "-50",
                                        Antenna = "1",
                                        Count = 1,
                                        FirstSeen = DateTime.Now,
                                        LastSeen = DateTime.Now
                                    };
                                    FireTagReceived(item);
                                }
                            }
                        }
                    }
                    Thread.Sleep(30);
                }
                catch (Exception ex)
                {
                    FireLog("Exception in 105EN ScanLoop: " + ex.Message);
                    Thread.Sleep(100);
                }
            }
        }

        public string ReadCardG2(string epcHex, byte memBank, byte wordPtr, byte wordNum, string passwordHex)
        {
            if (!IsConnected) return "Not connected";
            try
            {
                if (string.IsNullOrEmpty(passwordHex)) passwordHex = "00000000";
                byte addr = ComAddr;
                byte[] epcBytes = HexStringToByteArray(epcHex);
                byte[] pwdBytes = HexStringToByteArray(passwordHex);
                if (pwdBytes.Length < 4) Array.Resize(ref pwdBytes, 4);

                byte[] data = new byte[wordNum * 2];
                int errorcode = 0;
                byte epcLenWords = (byte)(epcBytes.Length / 2);

                int ret = StaticClassReaderB.ReadCard_G2(ref addr, epcBytes, memBank, wordPtr, wordNum, pwdBytes, 0, 0, 0, data, epcLenWords, ref errorcode, PortHandle);
                if (ret == 0)
                {
                    string hexResult = ByteArrayToHexString(data);
                    FireLog(string.Format("Read G2 Success: {0}", hexResult));
                    return hexResult;
                }
                else
                {
                    FireLog(string.Format("Read G2 Failed. Return: {0}, ErrorCode: {1}", ret, errorcode));
                    return null;
                }
            }
            catch (Exception ex)
            {
                FireLog("Exception in ReadCardG2: " + ex.Message);
                return null;
            }
        }

        public bool WriteCardG2(string epcHex, byte memBank, byte wordPtr, string writeDataHex, string passwordHex)
        {
            if (!IsConnected) return false;
            try
            {
                if (string.IsNullOrEmpty(passwordHex)) passwordHex = "00000000";
                byte addr = ComAddr;
                byte[] epcBytes = HexStringToByteArray(epcHex);
                byte[] pwdBytes = HexStringToByteArray(passwordHex);
                if (pwdBytes.Length < 4) Array.Resize(ref pwdBytes, 4);

                byte[] writeData = HexStringToByteArray(writeDataHex);
                byte writeLenWords = (byte)(writeData.Length / 2);
                int errorcode = 0;
                byte epcLenWords = (byte)(epcBytes.Length / 2);

                int ret = StaticClassReaderB.WriteCard_G2(ref addr, epcBytes, memBank, wordPtr, writeLenWords, writeData, pwdBytes, 0, 0, 0, 0, epcLenWords, ref errorcode, PortHandle);
                if (ret == 0)
                {
                    FireLog("Write G2 Success.");
                    return true;
                }
                else
                {
                    FireLog(string.Format("Write G2 Failed. Return: {0}, ErrorCode: {1}", ret, errorcode));
                    return false;
                }
            }
            catch (Exception ex)
            {
                FireLog("Exception in WriteCardG2: " + ex.Message);
                return false;
            }
        }

        public bool WriteEpcG2(string newEpcHex, string passwordHex)
        {
            if (!IsConnected) return false;
            try
            {
                if (string.IsNullOrEmpty(passwordHex)) passwordHex = "00000000";
                byte addr = ComAddr;
                byte[] pwdBytes = HexStringToByteArray(passwordHex);
                if (pwdBytes.Length < 4) Array.Resize(ref pwdBytes, 4);

                byte[] newEpcBytes = HexStringToByteArray(newEpcHex);
                byte epcLenWords = (byte)(newEpcBytes.Length / 2);
                int errorcode = 0;

                int ret = StaticClassReaderB.WriteEPC_G2(ref addr, pwdBytes, newEpcBytes, epcLenWords, ref errorcode, PortHandle);
                if (ret == 0)
                {
                    FireLog("WriteEPC_G2 Success: " + newEpcHex);
                    return true;
                }
                else
                {
                    FireLog(string.Format("WriteEPC_G2 Failed. Return: {0}, ErrorCode: {1}", ret, errorcode));
                    return false;
                }
            }
            catch (Exception ex)
            {
                FireLog("Exception in WriteEpcG2: " + ex.Message);
                return false;
            }
        }

        public bool Beep(byte activeTime, byte silentTime, byte times)
        {
            if (!IsConnected) return false;
            try
            {
                byte addr = ComAddr;
                int ret = StaticClassReaderB.BuzzerAndLEDControl(ref addr, activeTime, silentTime, times, PortHandle);
                return ret == 0;
            }
            catch { return false; }
        }

        public bool SetPower(byte powerDbm)
        {
            if (!IsConnected) return false;
            try
            {
                byte addr = ComAddr;
                int ret = StaticClassReaderB.SetPowerDbm(ref addr, powerDbm, PortHandle);
                FireLog(string.Format("SetPowerDbm({0}): {1}", powerDbm, ret));
                return ret == 0;
            }
            catch (Exception ex)
            {
                FireLog("Exception SetPowerDbm: " + ex.Message);
                return false;
            }
        }

        private byte[] HexStringToByteArray(string hex)
        {
            hex = hex.Replace(" ", "");
            if (hex.Length % 2 != 0) hex = "0" + hex;
            byte[] bytes = new byte[hex.Length / 2];
            for (int i = 0; i < bytes.Length; i++)
            {
                bytes[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
            }
            return bytes;
        }

        private string ByteArrayToHexString(byte[] bytes)
        {
            if (bytes == null) return "";
            StringBuilder sb = new StringBuilder(bytes.Length * 2);
            foreach (byte b in bytes)
            {
                sb.AppendFormat("{0:X2}", b);
            }
            return sb.ToString();
        }
    }
}
