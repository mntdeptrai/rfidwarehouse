using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.IO.Ports;
using System.Linq;
using System.Media;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Win32;
using RFIDReaderAPI;
using UHFDesktopApp.Models;
using UHFDesktopApp.Services;

namespace UHFDesktopApp
{
    public partial class MainWindow : Window
    {
        private readonly RFIDReaderService _rfidService = RFIDReaderService.Instance;
        private readonly UHFReader105ENService _105EnService = UHFReader105ENService.Instance;

        private readonly ObservableCollection<TagItem> _tagsList = new ObservableCollection<TagItem>();
        private readonly Dictionary<string, TagItem> _tagsDict = new Dictionary<string, TagItem>();

        private readonly ObservableCollection<DiscoveredDevice> _discoveredDevicesList = new ObservableCollection<DiscoveredDevice>();

        private DispatcherTimer _rateTimer;
        private DispatcherTimer _telemetryTimer;
        private int _recentReads = 0;
        private long _totalReads = 0;
        private bool _is105Mode = false;

        public MainWindow()
        {
            InitializeComponent();
            DgTags.ItemsSource = _tagsList;
            DgDiscoveredDevices.ItemsSource = _discoveredDevicesList;

            // Wire up Service events
            _rfidService.TagReceived += OnTagReceived;
            _rfidService.LogMessageReceived += OnLogReceived;
            _rfidService.ConnectionStateChanged += OnConnectionStateChanged;
            _rfidService.DeviceDiscovered += OnDeviceDiscovered;
            _rfidService.GpiTriggered += OnGpiTriggered;

            _105EnService.TagReceived += OnTagReceived;
            _105EnService.LogMessageReceived += OnLogReceived;
            _105EnService.ConnectionStateChanged += OnConnectionStateChanged;

            // Timer for tag read rate
            _rateTimer = new DispatcherTimer
            {
                Interval = TimeSpan.FromSeconds(1)
            };
            _rateTimer.Tick += (s, e) =>
            {
                TxtReadRate.Text = string.Format("{0}/s", _recentReads);
                _recentReads = 0;
            };
            _rateTimer.Start();

            // Telemetry timer for reader temperature
            _telemetryTimer = new DispatcherTimer
            {
                Interval = TimeSpan.FromSeconds(5)
            };
            _telemetryTimer.Tick += (s, e) =>
            {
                if (_rfidService.IsConnected && !_is105Mode)
                {
                    string temp = _rfidService.GetReaderTemperature();
                    if (!string.IsNullOrEmpty(temp) && temp != "N/A")
                    {
                        TxtReaderTemp.Text = temp + " °C";
                    }
                }
            };
            _telemetryTimer.Start();

            // Refresh COM ports list
            RefreshComPorts();
            Log("UHF RFID Desktop Suite Ready. Hopeland C# SDK 4.42 Loaded.");
        }

        private void RefreshComPorts()
        {
            try
            {
                string[] ports = SerialPort.GetPortNames();
                CmbComPorts.Items.Clear();
                CmbComPorts105.Items.Clear();

                foreach (string p in ports)
                {
                    CmbComPorts.Items.Add(p);
                    CmbComPorts105.Items.Add(p);
                }

                if (CmbComPorts.Items.Count > 0)
                {
                    CmbComPorts.SelectedIndex = 0;
                    CmbComPorts105.SelectedIndex = 0;
                }
            }
            catch (Exception ex)
            {
                Log("Error getting COM ports: " + ex.Message);
            }
        }

        #region Service Event Handlers

        private void OnTagReceived(TagItem tag)
        {
            Dispatcher.Invoke(() =>
            {
                _totalReads++;
                _recentReads++;
                TxtTotalReads.Text = _totalReads.ToString();

                string key = tag.EPC + "|" + tag.TID;

                if (_tagsDict.ContainsKey(key))
                {
                    var existing = _tagsDict[key];
                    existing.Count++;
                    existing.RSSI = tag.RSSI;
                    existing.Antenna = tag.Antenna;
                    existing.LastSeen = DateTime.Now;
                    if (!string.IsNullOrEmpty(tag.Frequency)) existing.Frequency = tag.Frequency;
                    if (!string.IsNullOrEmpty(tag.Phase)) existing.Phase = tag.Phase;
                    if (!string.IsNullOrEmpty(tag.UserData)) existing.UserData = tag.UserData;
                }
                else
                {
                    tag.Index = _tagsList.Count + 1;
                    _tagsDict[key] = tag;
                    _tagsList.Insert(0, tag);
                    TxtUniqueCount.Text = _tagsDict.Count.ToString();

                    if (ChkSoundBeep.IsChecked == true)
                    {
                        SystemSounds.Beep.Play();
                    }
                }
            });
        }

        private void OnLogReceived(string log)
        {
            Dispatcher.Invoke(() =>
            {
                Log(log);
            });
        }

        private void OnConnectionStateChanged(bool isConnected)
        {
            Dispatcher.Invoke(() =>
            {
                if (isConnected)
                {
                    TxtReaderStatus.Text = "CONNECTED";
                    TxtReaderStatus.Foreground = (Brush)FindResource("AccentGreen");
                    LedStatus.Background = (Brush)FindResource("AccentGreen");
                    BtnConnect.IsEnabled = false;
                    BtnDisconnect.IsEnabled = true;
                    BtnConnect105.IsEnabled = false;
                    BtnDisconnect105.IsEnabled = true;
                    BtnStartInventory.IsEnabled = true;
                }
                else
                {
                    TxtReaderStatus.Text = "DISCONNECTED";
                    TxtReaderStatus.Foreground = (Brush)FindResource("AccentRed");
                    LedStatus.Background = (Brush)FindResource("AccentRed");
                    BtnConnect.IsEnabled = true;
                    BtnDisconnect.IsEnabled = false;
                    BtnConnect105.IsEnabled = true;
                    BtnDisconnect105.IsEnabled = false;
                    BtnStartInventory.IsEnabled = false;
                    BtnStopInventory.IsEnabled = false;
                    TxtReaderTemp.Text = "N/A";
                }
            });
        }

        private void OnDeviceDiscovered(DiscoveredDevice dev)
        {
            Dispatcher.Invoke(() =>
            {
                if (!_discoveredDevicesList.Any(d => d.IP == dev.IP && d.MAC == dev.MAC))
                {
                    _discoveredDevicesList.Add(dev);
                }
            });
        }

        private void OnGpiTriggered(int index, int state)
        {
            Dispatcher.Invoke(() =>
            {
                Brush activeBrush = (Brush)FindResource("AccentGreen");
                Brush inactiveBrush = (Brush)FindResource("CardDarkBorder");
                string activeText = "HIGH (Đang kích hoạt)";
                string inactiveText = "LOW (Không tích cực)";

                if (index == 1)
                {
                    LedGpi1.Background = state == 1 ? activeBrush : inactiveBrush;
                    TxtGpi1State.Text = state == 1 ? activeText : inactiveText;
                }
                else if (index == 2)
                {
                    LedGpi2.Background = state == 1 ? activeBrush : inactiveBrush;
                    TxtGpi2State.Text = state == 1 ? activeText : inactiveText;
                }
                else if (index == 3)
                {
                    LedGpi3.Background = state == 1 ? activeBrush : inactiveBrush;
                    TxtGpi3State.Text = state == 1 ? activeText : inactiveText;
                }
                else if (index == 4)
                {
                    LedGpi4.Background = state == 1 ? activeBrush : inactiveBrush;
                    TxtGpi4State.Text = state == 1 ? activeText : inactiveText;
                }
            });
        }

        private void Log(string msg)
        {
            TxtLogConsole.AppendText(msg + Environment.NewLine);
            if (ChkAutoScrollLog != null && ChkAutoScrollLog.IsChecked == true)
            {
                TxtLogConsole.ScrollToEnd();
            }
        }

        #endregion

        #region Toolbar & Connection UI Handlers

        private void CmbSdkMode_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (PanelRfidReaderApi == null || Panel105En == null) return;
            _is105Mode = CmbSdkMode.SelectedIndex == 1;

            if (_is105Mode)
            {
                PanelRfidReaderApi.Visibility = Visibility.Collapsed;
                Panel105En.Visibility = Visibility.Visible;
                Log("Switched to 105EN USB Desktop Issuer Reader Mode.");
            }
            else
            {
                PanelRfidReaderApi.Visibility = Visibility.Visible;
                Panel105En.Visibility = Visibility.Collapsed;
                Log("Switched to Hopeland RFIDReaderAPI.dll Mode.");
            }
        }

        private void CmbConnType_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (PanelTcpParams == null || PanelTcpServerParams == null || PanelSerialParams == null) return;

            int idx = CmbConnType.SelectedIndex;
            PanelTcpParams.Visibility = idx == 0 ? Visibility.Visible : Visibility.Collapsed;
            PanelTcpServerParams.Visibility = idx == 1 ? Visibility.Visible : Visibility.Collapsed;
            PanelSerialParams.Visibility = idx == 2 ? Visibility.Visible : Visibility.Collapsed;
        }

        private void BtnRefreshCom_Click(object sender, RoutedEventArgs e)
        {
            RefreshComPorts();
        }

        private void BtnConnect_Click(object sender, RoutedEventArgs e)
        {
            int idx = CmbConnType.SelectedIndex;
            if (idx == 0) // TCP Client
            {
                string ip = TxtIp.Text.Trim();
                int port;
                if (!int.TryParse(TxtPort.Text.Trim(), out port)) port = 9090;
                _rfidService.ConnectTcp(ip, port);
            }
            else if (idx == 1) // TCP Server
            {
                string serverIp = TxtServerIp.Text.Trim();
                string serverPort = TxtServerPort.Text.Trim();
                _rfidService.StartTcpServer(serverIp, serverPort);
            }
            else if (idx == 2) // Serial
            {
                string port = CmbComPorts.Text;
                int baud = 115200;
                if (CmbBaudRate.SelectedItem != null)
                {
                    int.TryParse(((ComboBoxItem)CmbBaudRate.SelectedItem).Content.ToString(), out baud);
                }
                _rfidService.ConnectSerial(port, baud);
            }
            else // USB HID
            {
                _rfidService.ConnectUsb();
            }
        }

        private void BtnDisconnect_Click(object sender, RoutedEventArgs e)
        {
            if (CmbConnType.SelectedIndex == 1 && _rfidService.IsTcpServerRunning)
            {
                _rfidService.StopTcpServer();
            }
            _rfidService.Disconnect();
        }

        private void BtnQuickLanSearch_Click(object sender, RoutedEventArgs e)
        {
            MainTabs.SelectedIndex = 5; // Navigate to Tab 6 (LAN Search)
            BtnSearchLanDevices_Click(null, null);
        }

        private void BtnAutoConnect105_Click(object sender, RoutedEventArgs e)
        {
            _105EnService.AutoConnect();
        }

        private void BtnConnect105_Click(object sender, RoutedEventArgs e)
        {
            string portStr = CmbComPorts105.Text.Replace("COM", "").Trim();
            int port;
            if (!int.TryParse(portStr, out port)) port = 1;

            byte baud = 5; // 57600
            if (CmbBaudRate105.SelectedIndex == 1) baud = 6; // 115200
            else if (CmbBaudRate105.SelectedIndex == 2) baud = 2; // 38400
            else if (CmbBaudRate105.SelectedIndex == 3) baud = 0; // 9600
            _105EnService.Connect(port, baud);
        }

        private void BtnDisconnect105_Click(object sender, RoutedEventArgs e)
        {
            _105EnService.Disconnect();
        }

        private void BtnBeepTest_Click(object sender, RoutedEventArgs e)
        {
            _105EnService.Beep(1, 1, 2);
        }

        #endregion

        #region Tab 1: Live Inventory Handlers

        private eAntennaNo GetSelectedAntennas()
        {
            int mask = 0;
            if (ChkAnt1.IsChecked == true) mask |= (int)eAntennaNo._1;
            if (ChkAnt2.IsChecked == true) mask |= (int)eAntennaNo._2;
            if (ChkAnt3.IsChecked == true) mask |= (int)eAntennaNo._3;
            if (ChkAnt4.IsChecked == true) mask |= (int)eAntennaNo._4;
            if (ChkAnt5.IsChecked == true) mask |= (int)eAntennaNo._5;
            if (ChkAnt6.IsChecked == true) mask |= (int)eAntennaNo._6;
            if (ChkAnt7.IsChecked == true) mask |= (int)eAntennaNo._7;
            if (ChkAnt8.IsChecked == true) mask |= (int)eAntennaNo._8;

            if (mask == 0) mask = (int)eAntennaNo._1; // default to Ant 1
            return (eAntennaNo)mask;
        }

        private void BtnSelectAllAnt_Click(object sender, RoutedEventArgs e)
        {
            ChkAnt1.IsChecked = true;
            ChkAnt2.IsChecked = true;
            ChkAnt3.IsChecked = true;
            ChkAnt4.IsChecked = true;
            ChkAnt5.IsChecked = true;
            ChkAnt6.IsChecked = true;
            ChkAnt7.IsChecked = true;
            ChkAnt8.IsChecked = true;
        }

        private void BtnDeselectAllAnt_Click(object sender, RoutedEventArgs e)
        {
            ChkAnt1.IsChecked = true; // keep Ant 1
            ChkAnt2.IsChecked = false;
            ChkAnt3.IsChecked = false;
            ChkAnt4.IsChecked = false;
            ChkAnt5.IsChecked = false;
            ChkAnt6.IsChecked = false;
            ChkAnt7.IsChecked = false;
            ChkAnt8.IsChecked = false;
        }

        private void BtnStartInventory_Click(object sender, RoutedEventArgs e)
        {
            bool started = false;
            if (_is105Mode)
            {
                started = _105EnService.StartInventory();
            }
            else
            {
                eAntennaNo antMask = GetSelectedAntennas();
                int scanMode = CmbScanMode.SelectedIndex;
                started = _rfidService.StartInventory(antMask, eReadType.Inventory, scanMode);
            }

            if (started)
            {
                BtnStartInventory.IsEnabled = false;
                BtnStopInventory.IsEnabled = true;
            }
        }

        private void BtnStopInventory_Click(object sender, RoutedEventArgs e)
        {
            if (_is105Mode)
            {
                _105EnService.StopInventory();
            }
            else
            {
                _rfidService.StopInventory();
            }
            BtnStartInventory.IsEnabled = true;
            BtnStopInventory.IsEnabled = false;
        }

        private void BtnClearList_Click(object sender, RoutedEventArgs e)
        {
            _tagsList.Clear();
            _tagsDict.Clear();
            _totalReads = 0;
            _recentReads = 0;
            TxtUniqueCount.Text = "0";
            TxtTotalReads.Text = "0";
            TxtReadRate.Text = "0/s";
        }

        private void TxtSearchEpc_TextChanged(object sender, TextChangedEventArgs e)
        {
            string q = TxtSearchEpc.Text.Trim().ToLower();
            if (string.IsNullOrEmpty(q))
            {
                DgTags.ItemsSource = _tagsList;
            }
            else
            {
                DgTags.ItemsSource = _tagsList.Where(t => t.EPC.ToLower().Contains(q) || t.TID.ToLower().Contains(q)).ToList();
            }
        }

        private void BtnExportCsv_Click(object sender, RoutedEventArgs e)
        {
            if (_tagsList.Count == 0)
            {
                MessageBox.Show("Danh sách thẻ đang trống, không có dữ liệu để xuất!", "Thông báo", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            var sfd = new SaveFileDialog
            {
                Filter = "CSV File (*.csv)|*.csv|All Files (*.*)|*.*",
                FileName = string.Format("UHF_Inventory_{0:yyyyMMdd_HHmmss}.csv", DateTime.Now)
            };

            if (sfd.ShowDialog() == true)
            {
                try
                {
                    var sb = new StringBuilder();
                    sb.AppendLine("STT,EPC,TID,UserData,RSSI,Antenna,Count,Frequency,Phase,FirstSeen,LastSeen");
                    foreach (var tag in _tagsList)
                    {
                        sb.AppendLine(string.Format("{0},\"{1}\",\"{2}\",\"{3}\",\"{4}\",{5},{6},\"{7}\",\"{8}\",\"{9}\",\"{10}\"",
                            tag.Index, tag.EPC, tag.TID, tag.UserData, tag.RSSI, tag.Antenna, tag.Count, tag.Frequency, tag.Phase, tag.FirstSeen.ToString("yyyy-MM-dd HH:mm:ss.fff"), tag.LastSeen.ToString("yyyy-MM-dd HH:mm:ss.fff")));
                    }
                    File.WriteAllText(sfd.FileName, sb.ToString(), Encoding.UTF8);
                    Log("Đã xuất " + _tagsList.Count + " thẻ ra file: " + sfd.FileName);
                    MessageBox.Show("Xuất file CSV thành công!", "Thành công", MessageBoxButton.OK, MessageBoxImage.Information);
                }
                catch (Exception ex)
                {
                    Log("Lỗi khi xuất CSV: " + ex.Message);
                    MessageBox.Show("Lỗi: " + ex.Message, "Lỗi", MessageBoxButton.OK, MessageBoxImage.Error);
                }
            }
        }

        private void DgTags_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            var sel = DgTags.SelectedItem as TagItem;
            if (sel != null)
            {
                TxtTargetEpc.Text = sel.EPC;
                TxtRwMatchEpc.Text = sel.EPC;
                TxtLockTargetEpc.Text = sel.EPC;
                TxtKillTargetEpc.Text = sel.EPC;
            }
        }

        private void MenuCopyEpc_Click(object sender, RoutedEventArgs e)
        {
            var sel = DgTags.SelectedItem as TagItem;
            if (sel != null) Clipboard.SetText(sel.EPC);
        }

        private void MenuCopyTid_Click(object sender, RoutedEventArgs e)
        {
            var sel = DgTags.SelectedItem as TagItem;
            if (sel != null && !string.IsNullOrEmpty(sel.TID)) Clipboard.SetText(sel.TID);
        }

        private void MenuSendToRw_Click(object sender, RoutedEventArgs e)
        {
            var sel = DgTags.SelectedItem as TagItem;
            if (sel != null)
            {
                TxtTargetEpc.Text = sel.EPC;
                TxtRwMatchEpc.Text = sel.EPC;
                MainTabs.SelectedIndex = 1; // Tab Read / Write
            }
        }

        private void MenuSendToLock_Click(object sender, RoutedEventArgs e)
        {
            var sel = DgTags.SelectedItem as TagItem;
            if (sel != null)
            {
                TxtLockTargetEpc.Text = sel.EPC;
                TxtKillTargetEpc.Text = sel.EPC;
                MainTabs.SelectedIndex = 2; // Tab Security
            }
        }

        #endregion

        #region Tab 2: Read / Write Handlers

        private void BtnReadData_Click(object sender, RoutedEventArgs e)
        {
            int bankIdx = CmbRwBank.SelectedIndex;
            TagMemoryBank bank = bankIdx == 0 ? TagMemoryBank.EPC : (bankIdx == 1 ? TagMemoryBank.TID : (bankIdx == 2 ? TagMemoryBank.UserData : TagMemoryBank.Reserved));

            int offset = 2;
            int count = 6;
            int.TryParse(TxtRwOffset.Text.Trim(), out offset);
            int.TryParse(TxtRwCount.Text.Trim(), out count);

            string pwd = TxtRwPassword.Text.Trim();
            string matchEpc = TxtRwMatchEpc.Text.Trim();

            if (_is105Mode)
            {
                byte bankCode = (byte)(bankIdx == 0 ? 1 : (bankIdx == 1 ? 2 : (bankIdx == 2 ? 3 : 0)));
                string res = _105EnService.ReadCardG2(matchEpc, bankCode, (byte)offset, (byte)count, pwd);
                TxtRwData.Text = res != null ? res : "Lỗi đọc 105EN";
            }
            else
            {
                string res = _rfidService.ReadMemoryBank(bank, offset, count, pwd, matchEpc);
                TxtRwData.Text = res;
            }
        }

        private void BtnWriteData_Click(object sender, RoutedEventArgs e)
        {
            int bankIdx = CmbRwBank.SelectedIndex;
            TagMemoryBank bank = bankIdx == 0 ? TagMemoryBank.EPC : (bankIdx == 1 ? TagMemoryBank.TID : (bankIdx == 2 ? TagMemoryBank.UserData : TagMemoryBank.Reserved));

            int offset = 2;
            int.TryParse(TxtRwOffset.Text.Trim(), out offset);

            string hexData = TxtRwData.Text.Trim().Replace(" ", "");
            string pwd = TxtRwPassword.Text.Trim();
            string matchEpc = TxtRwMatchEpc.Text.Trim();

            if (string.IsNullOrEmpty(hexData))
            {
                MessageBox.Show("Vui lòng nhập dữ liệu Hex cần ghi!", "Thiếu dữ liệu", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            if (_is105Mode)
            {
                byte bankCode = (byte)(bankIdx == 0 ? 1 : (bankIdx == 1 ? 2 : (bankIdx == 2 ? 3 : 0)));
                bool ok = _105EnService.WriteCardG2(matchEpc, bankCode, (byte)offset, hexData, pwd);
                MessageBox.Show(ok ? "Ghi dữ liệu thành công!" : "Ghi dữ liệu thất bại!", "Kết quả", MessageBoxButton.OK, ok ? MessageBoxImage.Information : MessageBoxImage.Error);
            }
            else
            {
                string res = _rfidService.WriteMemoryBank(bank, offset, hexData, pwd, matchEpc);
                MessageBox.Show("Kết quả ghi thẻ: " + res, "Thông báo", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }

        private void BtnGenRandomEpc_Click(object sender, RoutedEventArgs e)
        {
            var rnd = new Random();
            var bytes = new byte[12]; // 12 bytes = 24 hex chars
            rnd.NextBytes(bytes);
            var sb = new StringBuilder();
            foreach (var b in bytes) sb.Append(b.ToString("X2"));
            TxtNewEpc.Text = sb.ToString();
        }

        private void BtnQuickWriteEpc_Click(object sender, RoutedEventArgs e)
        {
            string newEpc = TxtNewEpc.Text.Trim().Replace(" ", "");
            string targetEpc = TxtTargetEpc.Text.Trim().Replace(" ", "");
            string pwd = TxtRwPassword.Text.Trim();

            if (string.IsNullOrEmpty(newEpc))
            {
                MessageBox.Show("Vui lòng nhập mã EPC mới!", "Thiếu dữ liệu", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            if (_is105Mode)
            {
                bool ok = _105EnService.WriteEpcG2(newEpc, pwd);
                MessageBox.Show(ok ? "Ghi đè EPC mới thành công!" : "Ghi đè EPC thất bại!", "Kết quả", MessageBoxButton.OK, ok ? MessageBoxImage.Information : MessageBoxImage.Error);
            }
            else
            {
                string res = _rfidService.WriteEpc(newEpc, pwd, targetEpc);
                MessageBox.Show("Kết quả ghi EPC: " + res, "Thông báo", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }

        #endregion

        #region Tab 3: Security Handlers

        private void BtnApplyLock_Click(object sender, RoutedEventArgs e)
        {
            if (_is105Mode)
            {
                MessageBox.Show("Chức năng Khóa thẻ nâng cao được hỗ trợ tối ưu trên chuẩn RFIDReaderAPI.", "Thông báo", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            eLockArea area = (eLockArea)CmbLockArea.SelectedIndex;
            eLockType lockType = (eLockType)CmbLockType.SelectedIndex;
            string pwd = TxtLockPassword.Text.Trim();
            string matchEpc = TxtLockTargetEpc.Text.Trim();

            int ret = _rfidService.LockTag(area, lockType, pwd, matchEpc);
            MessageBox.Show(ret == 0 ? "Khóa thẻ thành công!" : ("Khóa thẻ thất bại (Mã: " + ret + ")"), "Kết quả", MessageBoxButton.OK, ret == 0 ? MessageBoxImage.Information : MessageBoxImage.Warning);
        }

        private void BtnKillTag_Click(object sender, RoutedEventArgs e)
        {
            string killPwd = TxtKillPassword.Text.Trim();
            string targetEpc = TxtKillTargetEpc.Text.Trim();

            if (string.IsNullOrEmpty(killPwd) || killPwd == "00000000")
            {
                MessageBox.Show("Mật khẩu Kill Password không được để trống hoặc 00000000!", "Cảnh báo", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            var dr = MessageBox.Show("BẠN CÓ CHẮC CHẮN MUỐN HỦY VĨNH VIỄN THẺ NÀY KHÔNG?\nThẻ sau khi hủy sẽ không thể đọc hay tái sử dụng!", "XÁC NHẬN HỦY THẺ", MessageBoxButton.YesNo, MessageBoxImage.Stop);
            if (dr == MessageBoxResult.Yes)
            {
                int ret = _rfidService.DestroyTag(killPwd, targetEpc);
                MessageBox.Show(ret == 0 ? "ĐÃ HỦY THẺ VĨNH VIỄN THÀNH CÔNG!" : ("Hủy thẻ thất bại (Mã: " + ret + ")"), "Kết quả", MessageBoxButton.OK, ret == 0 ? MessageBoxImage.Information : MessageBoxImage.Error);
            }
        }

        #endregion

        #region Tab 4: RF Power & Frequency Handlers

        private void SliderPower_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
        {
            if (TxtPower1 != null && SliderPower1 != null) TxtPower1.Text = ((int)SliderPower1.Value) + " dBm";
            if (TxtPower2 != null && SliderPower2 != null) TxtPower2.Text = ((int)SliderPower2.Value) + " dBm";
            if (TxtPower3 != null && SliderPower3 != null) TxtPower3.Text = ((int)SliderPower3.Value) + " dBm";
            if (TxtPower4 != null && SliderPower4 != null) TxtPower4.Text = ((int)SliderPower4.Value) + " dBm";
        }

        private void BtnApplyAllPower_Click(object sender, RoutedEventArgs e)
        {
            var dic = new Dictionary<int, int>
            {
                { 1, (int)SliderPower1.Value },
                { 2, (int)SliderPower2.Value },
                { 3, (int)SliderPower3.Value },
                { 4, (int)SliderPower4.Value }
            };

            int ret = _rfidService.SetAntennaPower(dic);
            MessageBox.Show(ret == 0 ? "Đã áp dụng công suất RF cho các anten thành công!" : "Cài đặt công suất thất bại", "Kết quả", MessageBoxButton.OK, ret == 0 ? MessageBoxImage.Information : MessageBoxImage.Warning);
        }

        private void BtnQueryPower_Click(object sender, RoutedEventArgs e)
        {
            var dic = _rfidService.GetAntennaPower();
            if (dic != null)
            {
                if (dic.ContainsKey(1)) SliderPower1.Value = dic[1];
                if (dic.ContainsKey(2)) SliderPower2.Value = dic[2];
                if (dic.ContainsKey(3)) SliderPower3.Value = dic[3];
                if (dic.ContainsKey(4)) SliderPower4.Value = dic[4];
                MessageBox.Show("Đã tải thông số công suất thành công!", "Thông báo", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }

        private void BtnApplyBaseBand_Click(object sender, RoutedEventArgs e)
        {
            int session = CmbSession.SelectedIndex;
            int target = CmbTarget.SelectedIndex;
            int ret = _rfidService.SetEPCBaseBand(0, session, target, 0);
            MessageBox.Show(ret == 0 ? "Đã áp dụng Gen2 Baseband thành công!" : "Cài đặt Baseband thất bại", "Kết quả", MessageBoxButton.OK, ret == 0 ? MessageBoxImage.Information : MessageBoxImage.Warning);
        }

        #endregion

        #region Tab 5: GPIO Handlers

        private void BtnRefreshGpi_Click(object sender, RoutedEventArgs e)
        {
            string state = _rfidService.GetGpiState();
            Log("Trạng thái GPI: " + state);
        }

        private void SetGpo(eGPO gpo, eGPOState state)
        {
            var dic = new Dictionary<eGPO, eGPOState>
            {
                { gpo, state }
            };
            _rfidService.SetGpoState(dic);
        }

        private void BtnGpo1On_Click(object sender, RoutedEventArgs e) { SetGpo(eGPO._1, (eGPOState)1); }
        private void BtnGpo1Off_Click(object sender, RoutedEventArgs e) { SetGpo(eGPO._1, (eGPOState)0); }

        private void BtnGpo2On_Click(object sender, RoutedEventArgs e) { SetGpo(eGPO._2, (eGPOState)1); }
        private void BtnGpo2Off_Click(object sender, RoutedEventArgs e) { SetGpo(eGPO._2, (eGPOState)0); }

        private void BtnGpoAllOn_Click(object sender, RoutedEventArgs e)
        {
            var dic = new Dictionary<eGPO, eGPOState>
            {
                { eGPO._1, (eGPOState)1 },
                { eGPO._2, (eGPOState)1 },
                { eGPO._3, (eGPOState)1 },
                { eGPO._4, (eGPOState)1 }
            };
            _rfidService.SetGpoState(dic);
        }

        private void BtnGpoAllOff_Click(object sender, RoutedEventArgs e)
        {
            var dic = new Dictionary<eGPO, eGPOState>
            {
                { eGPO._1, (eGPOState)0 },
                { eGPO._2, (eGPOState)0 },
                { eGPO._3, (eGPOState)0 },
                { eGPO._4, (eGPOState)0 }
            };
            _rfidService.SetGpoState(dic);
        }

        #endregion

        #region Tab 6: LAN Search & Device Management Handlers

        private void BtnSearchLanDevices_Click(object sender, RoutedEventArgs e)
        {
            _discoveredDevicesList.Clear();
            _rfidService.StartSearchLAN();
        }

        private void BtnStopSearchLan_Click(object sender, RoutedEventArgs e)
        {
            _rfidService.StopSearchLAN();
        }

        private void BtnConnectSelectedDevice_Click(object sender, RoutedEventArgs e)
        {
            var sel = DgDiscoveredDevices.SelectedItem as DiscoveredDevice;
            if (sel != null)
            {
                TxtIp.Text = sel.IP;
                TxtPort.Text = !string.IsNullOrEmpty(sel.ServerPort) ? sel.ServerPort : "9090";
                CmbConnType.SelectedIndex = 0; // TCP Client
                _rfidService.ConnectTcp(sel.IP, int.Parse(TxtPort.Text));
                MainTabs.SelectedIndex = 0; // Go back to Live Inventory
            }
            else
            {
                MessageBox.Show("Vui lòng chọn 1 thiết bị trong bảng để kết nối!", "Thông báo", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }

        private void DgDiscoveredDevices_MouseDoubleClick(object sender, MouseButtonEventArgs e)
        {
            BtnConnectSelectedDevice_Click(sender, e);
        }

        private void BtnGetNetConfig_Click(object sender, RoutedEventArgs e)
        {
            string net = _rfidService.GetNetworkConfig();
            if (!string.IsNullOrEmpty(net))
            {
                string[] parts = net.Split('|');
                if (parts.Length >= 3)
                {
                    TxtNetConfigIp.Text = parts[0];
                    TxtNetConfigMask.Text = parts[1];
                    TxtNetConfigGateway.Text = parts[2];
                }
            }
        }

        private void BtnSaveNetConfig_Click(object sender, RoutedEventArgs e)
        {
            string ip = TxtNetConfigIp.Text.Trim();
            string mask = TxtNetConfigMask.Text.Trim();
            string gw = TxtNetConfigGateway.Text.Trim();

            int ret = _rfidService.SetNetworkConfig(ip, mask, gw);
            MessageBox.Show(ret == 0 ? "Đã lưu cấu hình mạng thành công!" : "Lưu cấu hình mạng thất bại", "Kết quả", MessageBoxButton.OK, ret == 0 ? MessageBoxImage.Information : MessageBoxImage.Warning);
        }

        private void BtnGetDeviceInfo_Click(object sender, RoutedEventArgs e)
        {
            string info = _rfidService.GetReaderInfo();
            string temp = _rfidService.GetReaderTemperature();
            TxtDeviceInfo.Text = string.Format("Info: {0}\nNhiệt độ: {1} °C", info, temp);
        }

        private void BtnResetReader_Click(object sender, RoutedEventArgs e)
        {
            var dr = MessageBox.Show("Bạn có chắc chắn muốn khởi động lại đầu đọc?", "Xác nhận", MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (dr == MessageBoxResult.Yes)
            {
                _rfidService.ResetReader();
            }
        }

        #endregion

        #region Log Console Handlers

        private void BtnClearLog_Click(object sender, RoutedEventArgs e)
        {
            TxtLogConsole.Clear();
        }

        #endregion
    }
}
