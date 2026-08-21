using System;
using System.ComponentModel;

namespace UHFDesktopApp.Models
{
    public class TagItem : INotifyPropertyChanged
    {
        private int _index;
        private string _epc;
        private string _tid;
        private string _userData;
        private string _rssi;
        private string _antenna;
        private string _frequency;
        private string _phase;
        private long _count;
        private DateTime _firstSeen;
        private DateTime _lastSeen;

        public int Index
        {
            get { return _index; }
            set { _index = value; OnPropertyChanged("Index"); }
        }

        public string EPC
        {
            get { return _epc; }
            set { _epc = value; OnPropertyChanged("EPC"); }
        }

        public string TID
        {
            get { return _tid; }
            set { _tid = value; OnPropertyChanged("TID"); }
        }

        public string UserData
        {
            get { return _userData; }
            set { _userData = value; OnPropertyChanged("UserData"); }
        }

        public string RSSI
        {
            get { return _rssi; }
            set { _rssi = value; OnPropertyChanged("RSSI"); OnPropertyChanged("RssiDisplay"); }
        }

        public string Antenna
        {
            get { return _antenna; }
            set { _antenna = value; OnPropertyChanged("Antenna"); }
        }

        public string Frequency
        {
            get { return _frequency; }
            set { _frequency = value; OnPropertyChanged("Frequency"); }
        }

        public string Phase
        {
            get { return _phase; }
            set { _phase = value; OnPropertyChanged("Phase"); }
        }

        public long Count
        {
            get { return _count; }
            set { _count = value; OnPropertyChanged("Count"); }
        }

        public DateTime FirstSeen
        {
            get { return _firstSeen; }
            set { _firstSeen = value; OnPropertyChanged("FirstSeen"); }
        }

        public DateTime LastSeen
        {
            get { return _lastSeen; }
            set { _lastSeen = value; OnPropertyChanged("LastSeen"); OnPropertyChanged("LastSeenString"); }
        }

        public string LastSeenString
        {
            get { return _lastSeen.ToString("HH:mm:ss.fff"); }
        }

        public string RssiDisplay
        {
            get
            {
                if (string.IsNullOrEmpty(_rssi)) return "-";
                double d;
                if (double.TryParse(_rssi, out d))
                {
                    return string.Format("{0:F1} dBm", d);
                }
                return _rssi + " dBm";
            }
        }

        public event PropertyChangedEventHandler PropertyChanged;
        protected void OnPropertyChanged(string name)
        {
            var handler = PropertyChanged;
            if (handler != null) handler(this, new PropertyChangedEventArgs(name));
        }
    }
}
