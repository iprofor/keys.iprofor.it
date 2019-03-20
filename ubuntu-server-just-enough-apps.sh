#!/bin/bash
# transfer the following sections to another configuration script: configurations of unattended-upgrades, clamav, openssh-server


# @TODO ntpdate
# @TODO fail2ban http://www.servermom.org/how-to-install-fail2ban-to-protect-server-from-brute-force-ssh-login-attempts-ubuntu/
# @TODO rkhunter
# @TODO audit or intrusion system
# TODO:

# Prerequisites: an internet connection

# Made with love to be executed on an Ubuntu 16.04 LTS droplet

# Checking if the script is running as root
if [[ "$EUID" -ne 0 ]]; then
  echo "Sorry, you need to run this as root"
  exit 1
fi

# VARIABLES SECTION
# -----------------------------------

# Hostname
hstnm=hostname.iprofor.it
# SSHD config file
sshdc=/etc/ssh/sshd_config
# Sources.list file
slist=/etc/apt/sources.list
# SSH port
sshp=7539
# LoginGraceTime
sshlgt=1440m
# Installation log
rlog=~/installation.log
# Backup extension
bckp=bckp;
# Shortenned /dev/null
dn=/dev/null 2>&1
# ssh public key
sshkey=$(curl https://raw.githubusercontent.com/iprofor/keys.iprofor.it/master/servers.pub)

# Echoes that there is no X file
nofile_echo () {
  echo -e "\e[31mThere is no file named:\e[0m \e[1m\e[31m$@\e[0m";
}

# Echoes a standard message
std_echo () {
  echo -e "\e[32mPlease check it manually.\e[0m";
  echo -e "\e[1m\e[31mThis step stops here.\e[0m";
}

blnk_echo() {
  echo "" >> $rlog
}

# Echoes activation of a specific application option ($@)
enbl_echo () {
  echo -e "Activating \e[1m\e[34m$@\e[0m ...";
}

# Echoes that a specific application ($@) is being updated
upd_echo () {
  echo -e "Updating \e[1m\e[34m$@\e[0m application ...";
}

scn_echo () {
  echo -e "\e[1m\e[34m$@\e[0m is scanning the OS ..." >> $rlog
}

sctn_echo () {
  echo -e "\e[1m\e[33m$@\e[0m\n==================================================================================================" >> $rlog
}

# Echoes that a specific application ($@) is being installed
inst_echo () {
  echo -e "Installing \e[1m\e[34m$@\e[0m" >> $rlog
}

chg_unat10 () {
  # The following options will have unattended-upgrades check for updates every day while cleaning out the local download archive each week.
  echo "APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
  APT::Periodic::Unattended-Upgrade "1";" > $unat10;
}

# Backing up a given ($@) file/directory
bckup () {
  echo -e "Backing up: \e[1m\e[34m$@\e[0m ..." >> $rlog
  cp -r $@ $@_$(date +"%m-%d-%Y")."$bckp";
}

# Updates/upgrades the system
up () {
  sctn_echo UPDATES
  upvar="update upgrade dist-upgrade";
  for upup in $upvar; do
    echo -e "Executing \e[1m\e[34m$upup\e[0m" >> $rlog
    #apt-get -yqq $upup > /dev/null 2>&1 >> $rlog
    DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt-get -q -q -y -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" $upup >> $rlog
  done
  blnk_echo
}

# Installation
inst () {
  apt-get -yqqf install $@ > /dev/null >> $rlog
  blnk_echo
}

# ------------------------------------------
# END VARIABLES SECTION


cd ~;

# Forcing apt-get to access repos through IPV4
echo 'Acquire::ForceIPv4 "true";' | tee /etc/apt/apt.conf.d/99force-ipv4


## Updating/upgrading
up;


## Checking if the vital apps are already installed
# The list of the apps
appcliinstlld="ufw openssh-server unattended-upgrades"

# The main multi-loop for installing apps/libs
for a in $appcliinstlld; do
  if apt list --installed | grep -qwE "$a.*installed"; then
    echo -e "\e[1m\e[34m$a\e[0m is already installed";
  else
    inst_echo $a;
    inst $a;
  fi
done

blnk_echo


## UFW
sctn_echo FIREWALL "(UFW)"

bckup /etc/ufw/ufw.conf;

# Disabling IPV6 in UFW && Opening $sshp/tcp and Limiting incoming connections to the SSH port, enabling it (by default the rules are to deny incoming and allow outgoing)
(echo "IPV6=no" >> /etc/ufw/ufw.conf && ufw limit $sshp/tcp && ufw --force enable) >> $rlog

blnk_echo


## SSH Server configuration section
sctn_echo SSHD CONFIG

if [[ ! $(find . -name ".ssh") ]]; then
  # Create SSH folder with 700 permissions
  mkdir -m 700 ~/.ssh;

  # Authorized_keys file needs 644 permissions
  echo $sshkey > ~/.ssh/authorized_keys && chmod 644 ~/.ssh/authorized_keys;
fi

bckup $sshdc;

echo "Configuring SSHD Daemon ..." >> $rlog

# Disabling SSH password authentication, Switching default SSH port to $sshp && changing LoginGraceTime to 24h (1440m) && enabling #Banner /etc/issue.net
sed -i -re 's/^(ChallengeResponseAuthentication)([[:space:]]+)yes/\1\2'no'/' -e 's/^(\#)(PasswordAuthentication)([[:space:]]+)(.*)/\2\3\4/' -e 's/^(PasswordAuthentication)([[:space:]]+)yes/\1\2'no'/' -e 's/^(Port)([[:space:]]+)22/\1\2'$sshp'/' -e 's/^(LoginGraceTime)([[:space:]]+)120/\1\2'$sshlgt'/' -e 's/^(\#)(Banner)([[:space:]]+)(.*)/\2\3\4/'$sshdc;

service ssh restart


## Unattended-Upgrades configuration section
sctn_echo AUTOUPDATES "(Unattended-Upgrades)"

unat20=/etc/apt/apt.conf.d/20auto-upgrades;
unat50=/etc/apt/apt.conf.d/50unattended-upgrades;
unat10=/etc/apt/apt.conf.d/10periodic;

# Cheking the existence of the $unat20, $unat50, $unat10 configuration files
if [[ -f $unat20 ]] && [[ -f $unat50 ]] && [[ -f $unat10 ]]; then

  for i in $unat20 $unat50 $unat10; do
    bckup $i && mv $i*."$bckp" ~;
  done


  # Inserting the right values into it
  echo "APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
  APT::Periodic::Verbose "2";" > $unat20


  # Checking if line for security updates is uncommented, by default it is
  if [[ $(cat $unat50 | grep -wx '[[:space:]]"${distro_id}:${distro_codename}-security";') ]]; then

    chg_unat10;
  else
    echo "
// Automatically upgrade packages from these (origin:archive) pairs
Unattended-Upgrade::Allowed-Origins {
	"${distro_id}:${distro_codename}";
	"${distro_id}:${distro_codename}-security";
	// Extended Security Maintenance; doesn't necessarily exist for
	// every release and this system may not have it installed, but if
	// available, the policy for updates is such that unattended-upgrades
	// should also install from here by default.
	"${distro_id}ESM:${distro_codename}";
	//	"${distro_id}:${distro_codename}-updates";
	//	"${distro_id}:${distro_codename}-proposed";
	//	"${distro_id}:${distro_codename}-backports";
};

// List of packages to not update (regexp are supported)
Unattended-Upgrade::Package-Blacklist {
	//	"vim";
	//	"libc6";
	//	"libc6-dev";
	//	"libc6-i686";
};

// This option allows you to control if on a unclean dpkg exit
// unattended-upgrades will automatically run
//   dpkg --force-confold --configure -a
// The default is true, to ensure updates keep getting installed
//Unattended-Upgrade::AutoFixInterruptedDpkg "false";

// Split the upgrade into the smallest possible chunks so that
// they can be interrupted with SIGUSR1. This makes the upgrade
// a bit slower but it has the benefit that shutdown while a upgrade
// is running is possible (with a small delay)
//Unattended-Upgrade::MinimalSteps "true";

// Install all unattended-upgrades when the machine is shuting down
// instead of doing it in the background while the machine is running
// This will (obviously) make shutdown slower
//Unattended-Upgrade::InstallOnShutdown "true";

// Send email to this address for problems or packages upgrades
// If empty or unset then no email is sent, make sure that you
// have a working mail setup on your system. A package that provides
// 'mailx' must be installed. E.g. "user@example.com"
//Unattended-Upgrade::Mail "root";

// Set this value to "true" to get emails only on errors. Default
// is to always send a mail if Unattended-Upgrade::Mail is set
//Unattended-Upgrade::MailOnlyOnError "true";

// Do automatic removal of new unused dependencies after the upgrade
// (equivalent to apt-get autoremove)
Unattended-Upgrade::Remove-Unused-Dependencies "true";

// Automatically reboot *WITHOUT CONFIRMATION*
//  if the file /var/run/reboot-required is found after the upgrade
Unattended-Upgrade::Automatic-Reboot "false";

// If automatic reboot is enabled and needed, reboot at the specific
// time instead of immediately
//  Default: "now"
//Unattended-Upgrade::Automatic-Reboot-Time "02:00";

// Use apt bandwidth limit feature, this example limits the download
// speed to 70kb/sec
Acquire::http::Dl-Limit "200";" > $unat50

    chg_unat10;
  fi

  # The results of unattended-upgrades will be logged to /var/log/unattended-upgrades.
  # For more tweaks nano /etc/apt/apt.conf.d/50unattended-upgrades

  blnk_echo >> $rlog

else
  nofile_echo $unat20 or $unat50 or $unat10
  std_echo;
fi

blnk_echo

# END: Unattended-Upgrades configuration section


## Updating/upgrading
up;


## Installing necessary CLI apps
sctn_echo INSTALLATION

# The list of the apps
appcli="arp-scan clamav clamav-daemon clamav-freshclam curl git glances htop iptraf lm-sensors mc ntp ntpdate rcconf rig screen shellcheck sysbench sysv-rc-conf tmux tree whois"

# The main multi-loop for installing apps/libs
for a in $appcli; do
  inst_echo $a;
  inst $a;
done

blnk_echo


# ClamAV section: configuration and the first scan
sctn_echo ANTIVIRUS "(Clam-AV)" >> $rlog

clmcnf=/etc/clamav/freshclam.conf
rprtfldr=~/ClamAV-Reports

bckup $clmcnf;
mkdir -p $rprtfldr;

# Enabling "SafeBrowsing true" mode
enbl_echo SafeBrowsing >> $rlog
echo "SafeBrowsing true" >> $clmcnf;

# Restarting CLAMAV Daemons
/etc/init.d/clamav-daemon restart && /etc/init.d/clamav-freshclam restart;
# clamdscan -V s

# Scanning the whole system and palcing all the infected files list on a particular file
scn_echo ClamAv >> $rlog
# This one throws any kind of warnings and errors: clamscan -r / | grep FOUND >> $rprtfldr/clamscan_first_scan.txt >> $rlog
clamscan --recursive --no-summary --infected / 2>/dev/null | grep FOUND >> $rprtfldr/clamscan_first_scan.txt;

# Crontab: The daily scan
# This way, Anacron ensures that if the computer is off during the time interval when it is supposed to be scanned by the daemon, it will be scanned next time it is turned on, no matter today or another day.
echo -e "Creating a \e[1m\e[34mcronjob\e[0m for the ClamAV ..." >> $rlog
echo -e '#!/bin/bash\n\n/usr/bin/freshclam --quiet;\n/usr/bin/clamscan --recursive --exclude-dir=/media/ --no-summary --infected / 2>/dev/null >> '$rprtfldr'/clamscan_daily_$(date +"%m-%d-%Y").txt;' >> /etc/cron.daily/clamscan.sh && chmod 755 /etc/cron.daily/clamscan.sh;

blnk_echo

# END: ClamAV section: configuration and the first scan


# @NOTE Will have to modify this loop to echo "Everything went well"  otherwise echo that something went wrong
# if [[ "$EUID" -ne 0 ]]; then
# 	echo "Sorry, you need to run this as root"
# 	exit 1
# fi

echo "Everything finished!!!" >> $rlog
blnk_echo

exit 0;
