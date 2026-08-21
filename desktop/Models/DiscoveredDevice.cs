using System;
using System.ComponentModel;

namespace UHFDesktopApp.Models
{
    public class DiscoveredDevice : INotifyPropertyChanged
    {
        private string _mac;
        private string _ip;
        private string _mask;
        private string _gateway;
        private string _serverPort;
        private string _remoteIp;
        private string _remotePort;
        private string _workingMode;
        private string _deviceType;
        private string _connectState;

        public string MAC
        {
            get { return _mac; }
            set { _mac = value; OnPropertyChanged("MAC"); }
        }

        public string IP
        {
            get { return _ip; }
            set { _ip = value; OnPropertyChanged("IP"); }
        }

        public string Mask
        {
            get { return _mask; }
            set { _mask = value; OnPropertyChanged("Mask"); }
        }

        public string Gateway
        {
            get { return _gateway; }
            set { _gateway = value; OnPropertyChanged("Gateway"); }
        }

        public string ServerPort
        {
            get { return _serverPort; }
            set { _serverPort = value; OnPropertyChanged("ServerPort"); }
        }

        public string RemoteIP
        {
            get { return _remoteIp; }
            set { _remoteIp = value; OnPropertyChanged("RemoteIP"); }
        }

        public string RemotePort
        {
            get { return _remotePort; }
            set { _remotePort = value; OnPropertyChanged("RemotePort"); }
        }

        public string WorkingMode
        {
            get { return _workingMode; }
            set { _workingMode = value; OnPropertyChanged("WorkingMode"); }
        }

        public string DeviceType
        {
            get { return _deviceType; }
            set { _deviceType = value; OnPropertyChanged("DeviceType"); }
        }

        public string ConnectState
        {
            get { return _connectState; }
            set { _connectState = value; OnPropertyChanged("ConnectState"); }
        }

        public event PropertyChangedEventHandler PropertyChanged;
        protected void OnPropertyChanged(string name)
        {
            var handler = PropertyChanged;
            if (handler != null) handler(this, new PropertyChangedEventArgs(name));
        }
    }
}
