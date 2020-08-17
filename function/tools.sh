#swap设置
System_swap_settings(){
	swapSize=$(awk '/SwapTotal/{print $2}' /proc/meminfo)
	if [ "$swapSize" == 0 ];then
		while true; do
			echo -e "1) 512M\n2) 1G\n3) 2G\n4) 4G\n5) 8G\n"
			read -p "please select your swap size: " swapSelect			
			case $swapSelect in
				1) swapSize=524288;break;;
				2) swapSize=1048576;break;;
				3) swapSize=2097152;break;;
				4) swapSize=4194304;break;;
				5) swapSize=8388608;break;;
				*) echo "input error,please reinput."
			esac
		done

		swapLocationDefault="/swapfile"
		read -p "please input the swap file location(default:${swapLocationDefault},leave blank for default.): " swapLocation
		swapLocation=${swapLocation:=$swapLocationDefault}
		swapLocation=`filter_location ${swapLocation}`

		echo "start setting system swap..."
		mkdir -p `dirname $swapLocation`
		dd if=/dev/zero of=${swapLocation} bs=1024 count=${swapSize}
		mkswap ${swapLocation}
		swapon ${swapLocation}
		! grep "${swapLocation} swap swap defaults 0 0" /etc/fstab && echo "${swapLocation} swap swap defaults 0 0" >> /etc/fstab

		echo "swap settings complete."
		free -m
		exit

	else
		echo "Your system swap had been enabled,exit."
		exit
	fi	
}

#自定义mysql配置文件生成
make_mysql_my_cnf(){
	local memory=$1
	local storage=$2
	local mysqlDataLocation=$3
	local binlog=$4
	local replica=$5
	local my_cnf_location=$6
	local port_number=$7

	case $memory in
		256M)innodb_log_file_size=32M;innodb_buffer_pool_size=64M;key_buffer_size=64M;open_files_limit=512;table_definition_cache=50;table_open_cache=200;max_connections=50;;
		512M)innodb_log_file_size=32M;innodb_buffer_pool_size=128M;key_buffer_size=128M;open_files_limit=512;table_definition_cache=50;table_open_cache=200;max_connections=100;;
		1G)innodb_log_file_size=64M;innodb_buffer_pool_size=256M;key_buffer_size=256M;open_files_limit=1024;table_definition_cache=100;table_open_cache=400;max_connections=200;;
		2G)innodb_log_file_size=64M;innodb_buffer_pool_size=1G;key_buffer_size=512M;open_files_limit=1024;table_definition_cache=100;table_open_cache=400;max_connections=300;;
		4G)innodb_log_file_size=128M;innodb_buffer_pool_size=2G;key_buffer_size=1G;open_files_limit=2048;table_definition_cache=200;table_open_cache=800;max_connections=400;;
		8G)innodb_log_file_size=256M;innodb_buffer_pool_size=4G;key_buffer_size=2G;open_files_limit=4096;table_definition_cache=400;table_open_cache=1600;max_connections=400;;
		16G)innodb_log_file_size=512M;innodb_buffer_pool_size=10G;key_buffer_size=4G;open_files_limit=8192;table_definition_cache=600;table_open_cache=2000;max_connections=500;;
		32G)innodb_log_file_size=512M;innodb_buffer_pool_size=20G;key_buffer_size=10G;open_files_limit=65535;table_definition_cache=1024;table_open_cache=2048;max_connections=1000;;
		*) echo "input error,please input a number";;						
	esac

	#二进制日志
	if $binlog;then
		binlog="# BINARY LOGGING #\nlog-bin                        = ${mysqlDataLocation}/mysql-bin\nserver-id	= 1\nexpire-logs-days               = 14\nsync-binlog                    = 1"
		binlog=$(echo -e $binlog)
	else
		binlog=""
	fi	

	#复制节点
	if $replica;then
		replica="# REPLICATION #\nrelay-log                      = ${mysqlDataLocation}/relay-bin\nslave-net-timeout              = 60"
		replica=$(echo -e $replica)
	else
		replica=""
	fi	

	#设置myisam及innodb内存
	if [ "$storage" == "InnoDB" ];then
		key_buffer_size=32M
		if ! is_64bit && [[ `echo $innodb_buffer_pool_size | tr -d G` -ge 4 ]];then
			innodb_buffer_pool_size=2G
		fi	

	elif [ "$storage" == "MyISAM" ]; then
		innodb_log_file_size=32M
		innodb_buffer_pool_size=8M
		if ! is_64bit && [[ `echo $key_buffer_size | tr -d G` -ge 4 ]];then
			key_buffer_size=2G
		fi			
	fi

	echo "generate my.cnf..."
	sleep 1
	generate_time=$(date +%Y-%m-%d' '%H:%M:%S)
	cat >${my_cnf_location} <<EOF
# Generated at $generate_time

[mysql]

# CLIENT #
port                           = ${port_number}
socket                         = ${mysqlDataLocation}/mysql.sock

[mysqld]

# GENERAL #
port                           = ${port_number}
user                           = mysql
default-storage-engine         = ${storage}
socket                         = ${mysqlDataLocation}/mysql.sock
pid-file                       = ${mysqlDataLocation}/mysql.pid
skip-name-resolve
lower_case_table_names		   = 1

# MyISAM #
key-buffer-size                = ${key_buffer_size}

# INNODB #
#innodb-flush-method            = O_DIRECT
innodb-log-files-in-group      = 2
innodb-log-file-size           = ${innodb_log_file_size}
innodb-flush-log-at-trx-commit = 2
innodb-file-per-table          = 1
innodb-buffer-pool-size        = ${innodb_buffer_pool_size}

# CACHES AND LIMITS #
tmp-table-size                 = 32M
max-heap-table-size            = 32M
query-cache-type               = 0
query-cache-size               = 0
max-connections                = ${max_connections}
thread-cache-size              = 50
open-files-limit               = ${open_files_limit}
table-definition-cache         = ${table_definition_cache}
table-open-cache               = ${table_open_cache}


# SAFETY #
max-allowed-packet             = 16M
max-connect-errors             = 1000000

# DATA STORAGE #
datadir                        = ${mysqlDataLocation}

# LOGGING #
log-error                      = ${mysqlDataLocation}/mysql-error.log
log-queries-not-using-indexes  = 1
slow-query-log                 = 1
slow-query-log-file            = ${mysqlDataLocation}/mysql-slow.log

${binlog}

${replica}

EOF

	echo "generate done.my.cnf at ${my_cnf_location}"

}

#mysql配置文件生成工具
Generate_mysql_my_cnf(){
	#输入内存
	while true; do
		echo -e "1) 256M\n2) 512M\n3) 1G\n4) 2G\n5) 4G\n6) 8G\n7) 16G\n8) 32G\n"
		read -p "please input mysql server memory(ie.1 2 3): " mysqlMemory
		case $mysqlMemory in
			1) mysqlMemory=256M;break;;
			2) mysqlMemory=512M;break;;
			3) mysqlMemory=1G;break;;
			4) mysqlMemory=2G;break;;
			5) mysqlMemory=4G;break;;
			6) mysqlMemory=8G;break;;
			7) mysqlMemory=16G;break;;
			8) mysqlMemory=32G;break;;
			*) echo "input error,please input a number";;
		esac

	done

	#输入存储引擎
	while true; do
		echo -e "1) InnoDB(recommended)\n2) MyISAM\n"
		read -p "please input the default storage(ie.1 2): " storage
		case $storage in
			1) storage="InnoDB";break;;
			2) storage="MyISAM";break;;
			*) echo "input error,please input ie.1 2";;
		esac
	done

	#输入mysql data位置
	read -p "please input the mysql data location(default:/usr/local/mysql/data): " mysqlDataLocation
	mysqlDataLocation=${mysqlDataLocation:=/usr/local/mysql/data}
	mysqlDataLocation=`filter_location $mysqlDataLocation`

	#mysql端口设置
	while true;do
		read -p "mysql port number(default:3306,leave blank for default): " mysql_port_number
		mysql_port_number=${mysql_port_number:=3306}
		if verify_port "$mysql_port_number";then
			echo "mysql port number: $mysql_port_number"
			break
		else
			echo "port number $mysql_port_number is invalid,please reinput."
		fi	
	done

	#是否开启二进制日志
	yes_or_no "enable binlog [Y/n]: " "binlog=true;echo 'you select y,enable binlog'" "binlog=false;echo 'you select n,disable binlog.'"

	#是否为复制节点
	yes_or_no "mysql server will be a replica [N/y]: " "replica=true;echo 'you select y,setup replica config.'" "replica=false;echo 'you select n.'"

	make_mysql_my_cnf "$mysqlMemory" "$storage" "$mysqlDataLocation" "$binlog" "$replica" "$cur_dir/my.cnf" "$mysql_port_number"
	echo "you should copy this file to the right location."
	exit
}

#生成spec文件
make_rpm(){
	local name=$1
	local version=$2
	local location=$3
	local filesPackage=($4)
	local postCmd=$5
	local summary=$6
	local description=$7
	local preun=$8

	local release=`uname -r | awk -F'.' '{print $4}'`
	local arch=`uname -r | awk -F'.' '{print $NF}'`

	local rpmExportPath=$HOME/rpmbuild/BUILDROOT/${name}-${version}-${release}.${arch}/
	mkdir -p $HOME/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
	mkdir -p $rpmExportPath

	#复制文件
	echo "copying files to rpm location..."
	local filesList=''
	for file in ${filesPackage[@]};do
		cp --parents -a $file $rpmExportPath
		filesList="$file\n$filesList"
	done

	filesList=$(echo -e $filesList)

	cd $HOME/rpmbuild/SPECS

	cat >${name}.spec << EOF
Summary: ${summary}
License: 2-clause BSD-like license
Name: ${name}
Version: $version
Release: $release
Distribution: Linux
Packager: dantinr@163.com
%description
${description}
%post
${postCmd}
%files
$filesList
%preun
$preun
EOF

echo "creating ${name} rpm package,please wait for a while..."
rpmbuild -bb ${name}.spec

echo "${name} rpm create done.rpm is locate at $HOME/rpmbuild/RPMS/$arch/"
echo 
echo "you can excute below command to install rpm package: "
if [[ $name == "apache" ]];then
	echo "yum -x httpd -y install ${name}-${version}-${release}.${arch}.rpm"
else
	echo "yum -y install ${name}-${version}-${release}.${arch}.rpm"
fi
}

#生成nginx rpm包
create_nginx_rpm(){
	local name="nginx"
	local version=`${nginx_location}/sbin/nginx -v 2>&1 | awk -F'/' '{print $2}'`
	local location="${nginx_location}"
	local filesPackage="${nginx_location} /etc/init.d/nginx /home/wwwroot/ /usr/bin/ez /etc/ezhttp_info_do_not_del"
	local postCmd="groupadd www\nuseradd -M -s /bin/false -g www www\n/etc/init.d/nginx start"
	postCmd=$(echo -e $postCmd)
	local summary="nginx web server"
	local description="nginx web server"
	local preun="/etc/init.d/nginx stop"

	make_rpm "${name}" "$version" "$location" "$filesPackage" "$postCmd" "$summary" "$description" "$preun"
}

#生成apache rpm包
create_apache_rpm(){
	local name="apache"
	local version=`${apache_location}/bin/httpd -v | awk -F'[/ ]' 'NR==1{print $4}'`
	local location="${apache_location}"
	local filesPackage="${apache_location} /etc/init.d/httpd /home/wwwroot/ /usr/bin/ez /etc/ezhttp_info_do_not_del"
	local postCmd="groupadd www\nuseradd -M -s /bin/false -g www www\n/etc/init.d/httpd start"
	postCmd=$(echo -e $postCmd)
	local summary="apache web server"
	local description="apache web server"
	local preun="/etc/init.d/httpd stop"

	make_rpm "${name}" "$version" "$location" "$filesPackage" "$postCmd" "$summary" "$description" "$preun"

}

#生成php rpm包
create_php_rpm(){

	local name="php"
	local version=`${php_location}/bin/php -v | awk 'NR==1{print $2}'`
	local location="${php_location}"
	local filesPackage=''
	local postCmd=''
	local preun=''
	if ${php_location}/bin/php -ini | grep -q "with-apxs";then
		filesPackage="${php_location} /usr/bin/ez /etc/ezhttp_info_do_not_del"
	else
		filesPackage="${php_location} /etc/init.d/php-fpm /usr/bin/ez /etc/ezhttp_info_do_not_del"
		postCmd="groupadd www\nuseradd -M -s /bin/false -g www www\n/etc/init.d/php-fpm start"
		preun="/etc/init.d/php-fpm stop"
	fi
	local libiconv64=''
	local libiconv32=''
	local libmcrypt64=''
	local libmcrypt32=''

	[ -s "/usr/lib64/libiconv.so.2" ] && libiconv64=/usr/lib64/libiconv.so.2*
	[ -s "/usr/lib/libiconv.so.2" ] && libiconv32=/usr/lib/libiconv.so.2*
	[ -s "/usr/lib64/libmcrypt.so.4" ] && libmcrypt64=/usr/lib64/libmcrypt.so.4*
	[ -s "/usr/lib/libmcrypt.so.4" ] && libmcrypt32=/usr/lib/libmcrypt.so.4*

	if is_64bit;then
		filesPackage="$filesPackage ${libiconv32} ${libiconv64} ${libmcrypt32} ${libmcrypt64}"
	else
		filesPackage="$filesPackage ${libiconv32} ${libmcrypt32}"
	fi	
	postCmd=$(echo -e $postCmd)
	local summary="php engine"
	local description="php engine"

	make_rpm "${name}" "$version" "$location" "$filesPackage" "$postCmd" "$summary" "$description" "$preun"

}

#生成mysql rpm包
create_mysql_rpm(){
	local name="mysql"
	local version=`${mysql_location}/bin/mysql -V | awk '{print $5}' | tr -d ','`
	local location="${mysql_location}"
	local filesPackage=''
	for file in `ls ${mysql_location} | grep -v -E "data|mysql-test|sql-bench"`;do
		filesPackage="$filesPackage ${mysql_location}/$file"
	done

	filesPackage="$filesPackage /etc/init.d/mysqld /usr/bin/mysql /usr/bin/mysqldump /usr/bin/ez /etc/ezhttp_info_do_not_del"
	local mysql_data_location=`${mysql_location}/bin/mysqld --print-defaults  | sed -r -n 's#.*datadir=([^ ]+).*#\1#p'`

	local postCmd="useradd  -M -s /bin/false mysql\n${mysql_location}/scripts/mysql_install_db --basedir=${mysql_location} --datadir=${mysql_data_location}  --defaults-file=${mysql_location}/etc/my.cnf --user=mysql\nchown -R mysql ${mysql_data_location}\nservice mysqld start"
	if echo $version | grep -q "^5\.1\.";then
		postCmd="useradd  -M -s /bin/false mysql\n${mysql_location}/bin/mysql_install_db --basedir=${mysql_location} --datadir=${mysql_data_location}  --defaults-file=${mysql_location}/etc/my.cnf --user=mysql\nchown -R mysql ${mysql_data_location}\nservice mysqld start"
	fi

	postCmd=$(echo -e $postCmd)
	local summary="mysql server"
	local description="mysql server"
	local preun="service mysqld stop"

	make_rpm "${name}" "$version" "$location" "$filesPackage" "$postCmd" "$summary" "$description" "$preun"

}

#生成memcached rpm包
create_memcached_rpm(){
	local name="memcached"
	local version=`${memcached_location}/bin/memcached -h | awk 'NR==1{print $2}'`
	local location="${memcached_location}"
	local filesPackage="${memcached_location} /etc/init.d/memcached"
	local postCmd="/etc/init.d/memcached start"
	local summary="memcached cache server"
	local description="memcached cache server"
	local preun="/etc/init.d/memcached stop"

	make_rpm "${name}" "$version" "$location" "$filesPackage" "$postCmd" "$summary" "$description" "$preun"

}

#生成pureftpd rpm包
create_pureftpd_rpm(){

	local name="pureftpd"
	local version=`${pureftpd_location}/sbin/pure-ftpd -h | awk 'NR==1{print $2}' | tr -d v`
	local location="${pureftpd_location}"
	local filesPackage="${pureftpd_location} /etc/init.d/pureftpd /usr/bin/ez /etc/ezhttp_info_do_not_del"
	local postCmd="/etc/init.d/pureftpd start"
	local summary="pureftpd ftp server"
	local description="pureftpd ftp server"
	local preun="/etc/init.d/pureftpd stop"

	make_rpm "${name}" "$version" "$location" "$filesPackage" "$postCmd" "$summary" "$description" "$preun"

}


#rpm生成工具
Create_rpm_package(){
	if ! check_sys sysRelease centos;then
		echo "create rpm package tool is only support system centos/redhat."
		exit
	fi

	#安装rpmbuild工具
	echo "start install rpmbuild tool,please wait for a few seconds..."
	echo
	yum -y install rpm-build

	#检测rpmbuild命令是否存在
	check_command_exist "rpmbuild"

	echo "available software can be created rpm below:"
	for ((i=1;i<=${#rpm_support_arr[@]};i++ )); do echo -e "$i) ${rpm_support_arr[$i-1]}"; done
	echo
	packages_prompt="please select which software you would like to create rpm(ie.1 2 3): "
	while true
	do
		read -p "${packages_prompt}" rpmCreate
		rpmCreate=(${rpmCreate})
		unset packages wrong
		for i in ${rpmCreate[@]}
		do
			if [ "${rpm_support_arr[$i-1]}" == "" ];then
				packages_prompt="input errors,please input numbers(ie.1 2 3): ";
				wrong=1
				break
			else	
				packages="$packages ${rpm_support_arr[$i-1]}"
				wrong=0
			fi
		done
		[ "$wrong" == 0 ] && break
	done
	echo -e "your packages selection ${packages}"

	#输入nginx location
	if if_in_array Nginx "$packages";then
		while true; do
			read -p "please input nginx location(default:/usr/local/nginx): " nginx_location
			nginx_location=${nginx_location:=/usr/local/nginx}
			nginx_location=`filter_location $nginx_location`
			if [ ! -d "$nginx_location" ];then
				echo "$nginx_location not found or is not a directory."
			else
				break
			fi		
		done
		echo "nginx location: $nginx_location"
	fi

	#输入apache location
	if if_in_array Apache "$packages";then
		while true; do
			read -p "please input apache location(default:/usr/local/apache): " apache_location
			apache_location=${apache_location:=/usr/local/apache}
			apache_location=`filter_location $apache_location`
			if [ ! -d "$apache_location" ];then
				echo "$apache_location not found or is not a directory."
			else
				break
			fi		
		done
		echo "apache location: $apache_location"
	fi

	#输入php location
	if if_in_array PHP "$packages";then
		while true; do
			read -p "please input php location(default:/usr/local/php): " php_location
			php_location=${php_location:=/usr/local/php}
			php_location=`filter_location $php_location`
			if [ ! -d "$php_location" ];then
				echo "$php_location not found or is not a directory."
			else
				break
			fi		
		done
		echo "php location: $php_location"
	fi

	#输入mysql location
	if if_in_array MySQL "$packages";then
		while true; do
			read -p "please input mysql location(default:/usr/local/mysql): " mysql_location
			mysql_location=${mysql_location:=/usr/local/mysql}
			mysql_location=`filter_location $mysql_location`
			if [ ! -d "$mysql_location" ];then
				echo "$mysql_location not found or is not a directory."
			else
				break
			fi		
		done
		echo "mysql location: $mysql_location"
	fi

	#输入memcached location
	if if_in_array Memcached "$packages";then
		while true; do
			read -p "please input memcached location(default:/usr/local/memcached): " memcached_location
			memcached_location=${memcached_location:=/usr/local/memcached}
			memcached_location=`filter_location $memcached_location`
			if [ ! -d "$memcached_location" ];then
				echo "$memcached_location not found or is not a directory."
			else
				break
			fi		
		done
		echo "memcached location: $memcached_location"
	fi

	#输入pureftpd location
	if if_in_array PureFTPd "$packages";then
		while true; do
			read -p "please input pureftpd location(default:/usr/local/pureftpd): " pureftpd_location
			pureftpd_location=${pureftpd_location:=/usr/local/pureftpd}
			pureftpd_location=`filter_location $pureftpd_location`
			if [ ! -d "$pureftpd_location" ];then
				echo "$pureftpd_location not found or is not a directory."
			else
				break
			fi		
		done
		echo "pureftpd location: $pureftpd_location"
	fi			

	eval 
	if_in_array Nginx "$packages" &&  create_nginx_rpm
	if_in_array Apache "$packages" && create_apache_rpm
	if_in_array PHP "$packages" && create_php_rpm
	if_in_array MySQL "$packages" && create_mysql_rpm
	if_in_array Memcached "$packages" && create_memcached_rpm
	if_in_array PureFTPd "$packages" && create_pureftpd_rpm

	exit
}

#percona xtrabackup工具安装
Percona_xtrabackup_install(){
	if check_sys sysRelease ubuntu || check_sys sysRelease debian;then
		apt-key adv --keyserver keys.gnupg.net --recv-keys 1C4CBDCDCD2EFD2A
		local version_name=`get_ubuntu_version_name`
		if ! grep -q "http://repo.percona.com/apt" /etc/apt/sources.list;then
			echo -e "deb http://repo.percona.com/apt $version_name main\ndeb-src http://repo.percona.com/apt $version_name main\n" >>  /etc/apt/sources.list
		fi
		
		apt-get -y update
		apt-get -y install percona-xtrabackup

	elif check_sys sysRelease centos;then
		if is_64bit;then
			rpm -Uhv http://www.percona.com/downloads/percona-release/percona-release-0.0-1.x86_64.rpm
		else
			rpm -Uhv http://www.percona.com/downloads/percona-release/percona-release-0.0-1.i386.rpm
		fi

		yum -y install percona-xtrabackup
	else
		echo "sorry,the percona xtrabackup install tool do not support your system,please let me know and make it support."
	fi

}

#更改ssh server端口
Change_sshd_port(){
	local listenPort=`ss -nlpt | awk '/sshd/{print $4}' | grep -o -E "[0-9]+$" | awk 'NR==1{print}'`
	local configPort=`grep -v "^#" /etc/ssh/sshd_config | sed -n -r 's/^Port\s+([0-9]+).*/\1/p'`
	configPort=${configPort:=22}

	echo "the ssh server is listenning at port $listenPort."
	echo "the /etc/ssh/sshd_config is configured port $configPort."

	local newPort=''
	while true; do
		read -p "please input your new ssh server port(range 0-65535,greater than 1024 is recommended.): " newPort
		if verify_port "$newPort";then
			break
		else
			echo "input error,must be a number(range 0-65535)."
		fi
	done

	#备份配置文件
	echo "backup sshd_config to sshd_config_original..."
	cp /etc/ssh/sshd_config /etc/ssh/sshd_config_original

	#开始改端口
	if grep -q -E "^Port\b" /etc/ssh/sshd_config;then
		sed -i -r "s/^Port\s+.*/Port $newPort/" /etc/ssh/sshd_config
	elif grep -q -E "#Port\b" /etc/ssh/sshd_config; then
		sed -i -r "s/#Port\s+.*/Port $newPort/" /etc/ssh/sshd_config
	else
		echo "Port $newPort" >> /etc/ssh/sshd_config
	fi
	
	#重启sshd
	local restartCmd=''
	if check_sys sysRelease debian || check_sys sysRelease ubuntu; then
		restartCmd="service ssh restart"
	else
		if check_sys sysRelease centos && CentOSVerCheck 7;then
			restartCmd="/bin/systemctl restart sshd.service"
		else	
			restartCmd="service sshd restart"
		fi	
	fi
	$restartCmd
	sleep 1

	#验证是否成功
	local nowPort=`ss -nlpt | awk '/sshd/{print $4}' | grep -o -E "[0-9]+$" | awk 'NR==1{print}'`
	if [[ "$nowPort" == "$newPort" ]]; then
		echo "change ssh server port to $newPort successfully."
	else
		echo "fail to change ssh server port to $newPort."
		echo "rescore the backup file /etc/ssh/sshd_config_original to /etc/ssh/sshd_config..."
		\cp /etc/ssh/sshd_config_original /etc/ssh/sshd_config
		$restartCmd
	fi

	exit
}

#清空iptables表
clean_iptables_rule(){
	iptables -P INPUT ACCEPT
	iptables -P OUTPUT ACCEPT
	iptables -X
	iptables -F
}

#iptables首次设置
iptables_init(){
	yes_or_no "we'll clean all rules before configure iptables,are you sure?[Y/n]: " "clean_iptables_rule" "Iptables_settings"

	echo "start to add a iptables rule..."
	echo

	#列出监听端口
	echo "the server is listenning below address:"
	echo 
	ss -nlpt | awk 'BEGIN{printf("%-20s %-20s\n%-20s %-20s\n","Program name","Listen Address","------------","--------------")} /LISTEN/{sub("users:\(\(\"","",$6);sub("\".*","",$6);printf("%-20s %-20s\n",$6,$4)}' 
	echo
	#端口选择
	local ports=''
	local ports_arr=''
	while true; do
		read -p "please input one or more ports allowed(ie.22 80 3306): " ports
		ports_arr=($ports)
		local step=false
		for p in ${ports_arr[@]};do
			if ! verify_port "$p";then
				echo "your input is invalid."
				step=false
				break
			fi
			step=true
		done
		$step && break
		[ "$ports" == "" ] && echo "input can not be empty."
	done

	#检查端口是否包含ssh端口,否则自动加入,防止无法连接ssh
	local sshPort=`ss -nlpt | awk '/sshd/{print $4}' | grep -o -E "[0-9]+$" | awk 'NR==1{print}'`
	local sshNotInput=true
	for p in ${ports_arr[@]};do
		if [[ $p == "$sshPort" ]];then
			sshNotInput=false
		fi
	done

	$sshNotInput && ports="$ports $sshPort"

	#开始设置防火墙
	iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
	ports_arr=($ports)
	for p in ${ports_arr[@]};do
		iptables -A INPUT -p tcp -m tcp --dport $p -j ACCEPT
	done

	iptables -A INPUT -i lo -j ACCEPT
	iptables -A INPUT -p icmp -m icmp --icmp-type 8 -j ACCEPT
	iptables -A INPUT -p icmp -m icmp --icmp-type 11 -j ACCEPT
	iptables -P INPUT DROP

	save_iptables
	list_iptables

	#设置内核参数
	if [ -f /proc/sys/net/ipv4/ip_conntrack_max ];then
		echo 665536  > /proc/sys/net/ipv4/ip_conntrack_max
		grep -q "net.ipv4.ip_conntrack_max = 665536" /etc/sysctl.conf || echo "net.ipv4.ip_conntrack_max = 665536" >> /etc/sysctl.conf

		echo 3600 > /proc/sys/net/ipv4/nf_conntrack_tcp_timeout_established
		grep -q "net.ipv4.nf_conntrack_tcp_timeout_established = 3600" /etc/sysctl.conf || echo "net.ipv4.nf_conntrack_tcp_timeout_established = 3600" >> /etc/sysctl.conf
	fi 

	if [ -f /proc/sys/net/netfilter/nf_conntrack_max ];then
		echo 665536  > /proc/sys/net/netfilter/nf_conntrack_max
		grep -q "net.netfilter.nf_conntrack_max = 665536" /etc/sysctl.conf || echo "net.netfilter.nf_conntrack_max = 665536" >> /etc/sysctl.conf

		echo 3600  > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established
		grep -q "net.netfilter.nf_conntrack_tcp_timeout_established = 3600" /etc/sysctl.conf || echo "net.netfilter.nf_conntrack_tcp_timeout_established = 3600" >> /etc/sysctl.conf		
	fi
	
	if [ -f /proc/sys/net/ipv4/netfilter/ip_conntrack_max ];then
		echo 665536 > /proc/sys/net/ipv4/netfilter/ip_conntrack_max
		grep -q "net.ipv4.netfilter.ip_conntrack_max = 665536" /etc/sysctl.conf || echo "net.ipv4.netfilter.ip_conntrack_max = 665536" >> /etc/sysctl.conf

		echo 3600 > /proc/sys/net/ipv4/netfilter/ip_conntrack_tcp_timeout_established
		grep -q "net.ipv4.netfilter.ip_conntrack_tcp_timeout_established = 3600" /etc/sysctl.conf || echo "net.ipv4.netfilter.ip_conntrack_tcp_timeout_established = 3600" >> /etc/sysctl.conf		
	fi

	[[ -f /sys/module/nf_conntrack/parameters/hashsize ]] && echo 83456 > /sys/module/nf_conntrack/parameters/hashsize
	[[ -f /sys/module/ip_conntrack/parameters/hashsize ]] && echo 83456 > /sys/module/ip_conntrack/parameters/hashsize
	echo "options nf_conntrack hashsize=83456" > /etc/modprobe.d/nf_conntrack_hashsize.conf

	echo "configure iptables done."
}

#增加规则
add_iptables_rule(){
	#协议选择
	while true; do
		echo -e "1) tcp\n2) udp\n3) all\n"
		read -p "please specify the Protocol(default:tcp): " protocol
		protocol=${protocol:=1}
		case  $protocol in
			1) protocol="-p tcp";break;;
			2) protocol="-p udp";break;;
			3) protocol="";break;;
			*) echo "input error,please input a number(ie.1 2 3)";;
		esac
	done

	#来源ip选择
	while true; do
		read -p "please input the source ip address(ie. 8.8.8.8 192.168.0.0/24,leave blank for all.): " sourceIP
		if [[ $sourceIP != "" ]];then
			local ip=`echo $sourceIP | awk -F'/' '{print $1}'`
			local mask=`echo $sourceIP | awk -F'/' '{print $2}'`
			local step1=false
			local step2=false
			if [[ $mask != "" ]];then
				if echo $mask | grep -q -E "^[0-9]+$" && [[ $mask -ge 0 ]] && [[ $mask -le 32 ]];then
					step1=true
				fi	
			else
				step1=true
			fi	
			
			if verify_ip "$ip";then
				step2=true
			fi
			
			if $step1 && $step2;then
				sourceIP="-s $sourceIP"
				break
			else
				echo "the ip is invalid."
			fi
		else
			break
		fi		
	done

	#端口选择
	local port=''
	if [[ $protocol != "" ]];then
		while true; do
			read -p "please input one port(ie.3306,leave blank for all): " port
			if [[ $port != "" ]];then
				if  verify_port "$port";then
					port="--dport $port"
					break
				else
					echo "your input is invalid."
				fi
			else
				break
			fi	
		done
	fi	

	#动作选择
	while true; do
		echo -e "1) ACCEPT\n2) DROP\n"
		read -p "select action(default:ACCEPT): " action
		action=${action:=1}
		case $action in
			1) action=ACCEPT;break;;
			2) action=DROP;break;;
			*) echo "input error,please input a number(ie.1 2)."
		esac
	done

	#开始添加记录
	local cmd='-A'
	if [[ "$action" == "ACCEPT" ]];then
		cmd="-A"
	elif [[ "$action" == "DROP" ]]; then
		cmd="-I"
	fi
	
	if iptables $cmd INPUT $protocol $sourceIP $port -j $action;then
		echo "add iptables rule successfully."
	else
		echo "add iptables rule failed."
	fi
	save_iptables
	list_iptables
}

#删除规则
delete_iptables_rule(){
	iptables -nL INPUT --line-number --verbose
	echo
	while true; do
		read -p "please input the number according to the first column: " number
		if echo "$number" | grep -q -E "^[0-9]+$";then
			break
		else
			echo "input error,please input a number."
		fi		
	done

	#开始删除规则
	if iptables -D INPUT $number;then
		echo "delete the iptables rule successfully."
	else
		echo "delete the iptables rule failed."
	fi
	save_iptables
	list_iptables
}

#保存iptables 
save_iptables(){
	#保存规则
	if check_sys sysRelease ubuntu || check_sys sysRelease debian;then
		iptables-save > /etc/iptables.up.rule
	elif check_sys sysRelease centos;then
		service iptables save
	fi
}

#开机加载iptables
load_iptables_onboot(){
	if check_sys sysRelease ubuntu || check_sys sysRelease debian;then
		if [[ ! -s "/etc/network/if-pre-up.d/iptablesload" ]]; then
			cat >/etc/network/if-pre-up.d/iptablesload<<EOF
#!/bin/sh
iptables-restore < /etc/iptables.up.rule
exit 0
EOF

		fi

		if [[ ! -s "/etc/network/if-post-down.d/iptablessave" ]]; then
			cat >/etc/network/if-post-down.d/iptablessave<<EOF
#!/bin/sh
iptables-save -c > /etc/iptables.up.rule
exit 0
EOF

		fi

		chmod +x /etc/network/if-post-down.d/iptablessave /etc/network/if-pre-up.d/iptablesload

	elif check_sys sysRelease centos;then
		if CentOSVerCheck 7;then
			systemctl enable iptables.service
		else	
			chkconfig iptables on
		fi	
	fi	
}

#停止ipables
stop_iptables(){
	save_iptables
	clean_iptables_rule
	list_iptables
}

#恢复iptables
rescore_iptables(){

	if check_sys sysRelease ubuntu || check_sys sysRelease debian;then
		if [ -s "/etc/iptables.up.rule" ];then
			iptables-restore < /etc/iptables.up.rule
			echo "rescore iptables done."
		else
			echo "/etc/iptables.up.rule not found,can not be rescore iptables."
		fi	
	elif check_sys sysRelease centos;then
		service iptables restart
		echo "rescore iptables done."
	fi
	list_iptables
}

#列出iptables
list_iptables(){
	iptables -nL INPUT --verbose
}
#iptales设置
Iptables_settings(){
	check_command_exist "iptables"
	# centos7 need to install iptables-services package
	if check_sys sysRelease centos && CentOSVerCheck 7;then
		if [[ ! -f "/etc/sysconfig/iptables" ]]; then
			yum install -y iptables-services
		fi
	fi

	load_iptables_onboot

	local select=''
	while true; do
		echo -e "1) clear all record,setting from nothing.\n2) add a iptables rule.\n3) delete any rule.\n4) backup rules and stop iptables.\n5) rescore iptables\n6) list iptables rules\n7) exit the script\n" 
		read -p "please input your select(ie 1): " select
		case  $select in
			1) iptables_init;;
			2) add_iptables_rule;;
			3) delete_iptables_rule;;
			4) stop_iptables;;
			5) rescore_iptables;;
			6) list_iptables;;
            7) exit;;
			*) echo "input error,please input a number.";;
		esac
	done
}

#开启或关闭共享扩展
Enable_disable_php_extension(){
	#获取php路径
	if [[ $phpConfig == "" ]];then
		while true; do
			read -p "please input the php config location(default:/usr/local/php/bin/php-config): " phpConfig
			phpConfig=${phpConfig:=/usr/local/php/bin/php-config}
			phpConfig=`filter_location "$phpConfig"`
			if check_php_config "$phpConfig";then
				break
			else
				echo "php config $phpConfig is invalid."
			fi	
		done
	fi	

	enabled_extensions=`$(get_php_bin "$phpConfig") -m | awk '$0 ~/^[a-zA-Z]/{printf $0" " }' | tr "[A-Z]" "[a-z]"`
	extension_dir=`get_php_extension_dir "$phpConfig"`
	shared_extensions=`cd $extension_dir;ls *.so | awk -F'.' '{print $1}'`
	shared_extensions_arr=($shared_extensions)
	echo "extension          state"
	echo "---------          -----"
	for extension in ${shared_extensions_arr[@]};do 
		if if_in_array $extension "$enabled_extensions";then
			state="enabled"
		else
			state="disabled"
		fi
		printf "%-15s%9s\n" $extension $state	

	done

	#输入扩展
	while true; do
		echo
		read -p "please input the extension you'd like to enable or disable(ie. curl): " extensionName
		if [[ $extensionName == "" ]];then
			echo "input can not be empty."
		elif if_in_array $extensionName "$shared_extensions";then
			break
		else
			echo "sorry,the extension $extensionName is not found."
		fi	
	done

	#开始启用或关闭扩展
	if if_in_array $extensionName "$enabled_extensions";then
		#关闭扩展
		sed -i "/extension=$extensionName.so/d" $(get_php_ini "$phpConfig")
		enabled_extensions=`$(get_php_bin "$phpConfig") -m | awk '$0 ~/^[a-zA-Z]/{printf $0" " }' | tr "[A-Z]" "[a-z]"`
		if if_in_array $extensionName "$enabled_extensions";then
			echo "disable extension $extensionName failed."
		else
			echo "disable extension $extensionName successfully."
		fi		
	else
		#开启扩展
		if [[ "$extensionName" == "opcache" ]]; then
			echo "zend_extension=${extensionName}.so" >> $(get_php_ini "$phpConfig")
		else
			echo "extension=${extensionName}.so" >> $(get_php_ini "$phpConfig")
		fi
			
		enabled_extensions=`$(get_php_bin "$phpConfig")  -m | awk '$0 ~/^[a-zA-Z]/{printf $0" " }' | tr "[A-Z]" "[a-z]"`
		if if_in_array $extensionName "$enabled_extensions";then
			echo "enable extension $extensionName successfully."
		else
			echo "enable extension $extensionName failed."
		fi
	fi	

	yes_or_no "do you want to continue enable or disable php extensions[Y/n]: " "Enable_disable_php_extension" "echo 'restarting php to take modifies affect...';restart_php;exit"
}

#设置时区及同步时间
Set_timezone_and_sync_time(){
	echo "current timezone is $(date +%z)"
	echo "current time is $(date +%Y-%m-%d" "%H:%M:%S)"
	echo
	yes_or_no "would you like to change the timezone[Y/n]: " "echo 'you select change the timezone.'" "echo 'you select do not change the timezone.'"
	if [[ $yn == "y" ]]; then
		set_timezone
	fi

	sync_time
	echo "current timezone is $(date +%z)"
	echo "current time is $(date +%Y-%m-%d" "%H:%M:%S)"	

}

set_timezone(){
	timezone=`tzselect`
	echo "start to change the timezone to $timezone..."
	cp /usr/share/zoneinfo/$timezone /etc/localtime	
}

sync_time(){
	echo "start to sync time and add sync command to cronjob..."
	if check_sys sysRelease ubuntu || check_sys sysRelease debian;then
		apt-get -y update
		apt-get -y install ntpdate
		check_command_exist ntpdate
		/usr/sbin/ntpdate -u pool.ntp.org
		! grep -q "/usr/sbin/ntpdate -u pool.ntp.org" /var/spool/cron/crontabs/root > /dev/null 2>&1 && echo "*/10 * * * * /usr/sbin/ntpdate -u pool.ntp.org > /dev/null 2>&1;/sbin/hwclock -w"  >> /var/spool/cron/crontabs/root
		service cron restart
	elif check_sys sysRelease centos; then
		yum -y install ntpdate
		check_command_exist ntpdate
		/usr/sbin/ntpdate -u pool.ntp.org
		! grep -q "/usr/sbin/ntpdate -u pool.ntp.org" /var/spool/cron/root > /dev/null 2>&1 && echo "*/10 * * * * /usr/sbin/ntpdate -u pool.ntp.org > /dev/null 2>&1;/sbin/hwclock -w" >> /var/spool/cron/root
		service crond restart
	fi
	/sbin/hwclock -w	
}

#初始化mysql数据库
Initialize_mysql_server(){
	while true; do
		read -p "please input mysql install location(default:/usr/local/mysql): " mysql_location
		mysql_location=${mysql_location:=/usr/local/mysql}
		version=`${mysql_location}/bin/mysql -V  | grep -o -E "[0-9]+\.[0-9]+\.[0-9]+"`
		if [[ $version == "" ]]; then
			echo "can not get mysql version,may be the location of you input is invalid."
		else
			break
		fi
	done

	read -p "please input mysql data location(default:${mysql_location}/data/): " mysql_data_location
	mysql_data_location=${mysql_data_location:=${mysql_location}/data/}
	mysql_data_location=`filter_location $mysql_data_location`

	read -p "please input mysql root password(default:root): " mysql_root_pass
	mysql_root_pass=${mysql_root_pass:=root}

	service mysqld stop
	sleep 1
	rm -rf ${mysql_data_location}/mysql/
	if echo $version | grep -q "5\.1";then
		${mysql_location}/bin/mysql_install_db --basedir=${mysql_location} --datadir=${mysql_data_location}  --defaults-file=${mysql_location}/etc/my.cnf --user=mysql
	elif echo $version | grep -q "5\.5";then
		${mysql_location}/scripts/mysql_install_db --basedir=${mysql_location} --datadir=${mysql_data_location} --defaults-file=${mysql_location}/etc/my.cnf --user=mysql
	elif echo $version | grep -q "5\.6";then
		yes_or_no "below operation will be lose all of your mysql data,do you want to continue?[N/y]: " "rm -f ${mysql_data_location}/ibdata1;rm -rf ${mysql_data_location}/ib_logfile*" "exit 1"
		${mysql_location}/scripts/mysql_install_db --basedir=${mysql_location} --datadir=${mysql_data_location} --defaults-file=${mysql_location}/etc/my.cnf --user=mysql
	fi
	
	chown -R mysql ${mysql_location} ${mysql_data_location}
	service mysqld start
	sleep 1
	${mysql_location}/bin/mysqladmin -u root password "$mysql_root_pass"
	echo "initialize mysql done."
}

#添加chroot shell用户
Add_chroot_shell_user(){
	while true; do
		echo -e "1) install jailkit.\n2) jail exist user.\n3) add a new user and jail it.\n4) exit the script\n"
		read -p "please input your select(ie 1): " select
		case  $select in
			1) install_jailkit;;
			2) jail_exist_user;;
			3) jail_new_user;;
            4) exit;;
			*) echo "input error,please input a number.";;
		esac
	done

	exit
}

#安装jailkit
install_jailkit(){
	if [[ -s /usr/local/jailkit/sbin/jk_init ]];then
		echo "file /usr/local/jailkit/sbin/jk_init found,maybe jailkit had been installed."
	else
		download_file  "${jailkit_filename}.tar.gz"
		cd $cur_dir/soft/
		tar xzvf ${jailkit_filename}.tar.gz
		cd ${jailkit_filename}
		make clean
		error_detect "./configure --prefix=/usr/local/jailkit"
		error_detect "make"
		error_detect "make install"
		cp extra/jailkit /etc/init.d/jailkit
		chmod +x /etc/init.d/jailkit
		sed -i 's#JK_SOCKETD=.*#JK_SOCKETD=/usr/local/jailkit/sbin/jk_socketd#' /etc/init.d/jailkit
		boot_start jailkit
		/usr/local/jailkit/sbin/jk_init -v -j /home/chroot sftp scp jk_lsh netutils extendedshell
		service jailkit start
		echo
		echo "please press ctrl+c to exit the scripts."
	fi	
}

#把已存在的用户加入到限制shell
jail_exist_user(){
	if [[ -s /usr/local/jailkit/sbin/jk_init ]];then
		while true; do
			read -p "please input username: " username
			if [[ $username == "" ]]; then
				echo "username could not be empty."
			elif ! awk -F: '{print $1}' /etc/passwd | grep -q -E "^${username}$"; then
				echo "username $username not found."
			else
				break
			fi
		done

		/usr/local/jailkit/sbin/jk_jailuser -m -n -j /home/chroot --shell=/bin/bash $username
	else
		echo "/usr/local/jailkit/sbin/jk_init not found,maybe jailkit is not installed"
	fi	
}

#新添加用户并限制shell
jail_new_user(){
	if [[ -s /usr/local/jailkit/sbin/jk_init ]];then
		while true; do
			read -p "please input username: " username
			if [[ $username == "" ]]; then
				echo "username could not be empty."
			else
				break
			fi
		done

		while true; do
			read -p "please input username $username password: " password
			if [[ $password == "" ]]; then
				echo "password could not be empty."
			else
				break
			fi
		done

		useradd $username -m
		echo $username:$password | chpasswd	
		/usr/local/jailkit/sbin/jk_jailuser -m -n -j /home/chroot --shell=/bin/bash $username
	else
		echo "/usr/local/jailkit/sbin/jk_init not found,maybe jailkit is not installed"
	fi		
}

#网络分析工具
Network_analysis(){
	LANG=c
	export LANG	
	while true; do
		echo -e "1) real time traffic.\n2) tcp traffic and connection overview.\n3) udp traffic overview\n4) http request count\n5) exit the script\n"
		read -p "please input your select(ie 1): " select
		case  $select in
			1) realTimeTraffic;;
			2) tcpTrafficOverview;;
			3) udpTrafficOverview;;
			4) httpRequestCount;;
            5) exit;;
			*) echo "input error,please input a number.";;
		esac
	done	
}

#实时流量
realTimeTraffic(){
	local eth=""
	local nic_arr=(`ip addr | awk  -F'[: @]' '/^[0-9]/{if($3 != "lo"){print $3}}'`)
	local nicLen=${#nic_arr[@]}
	if [[ $nicLen -eq 0 ]]; then
		echo "sorry,I can not detect any network device,please report this issue to author."
		exit 1
	elif [[ $nicLen -eq 1 ]]; then
		eth=$nic_arr
	else
		display_menu nic
		eth=$nic
	fi	

	local clear=true
	local eth_in_peak=0
	local eth_out_peak=0
	local eth_in=0
	local eth_out=0

	while true;do
		#移动光标到0:0位置
		printf "\033[0;0H"
		#清屏并打印Now Peak
		[[ $clear == true ]] && printf "\033[2J" && echo "$eth--------Now--------Peak-----------"
		traffic_be=(`awk -v eth=$eth -F'[: ]+' '{if ($0 ~eth){print $3,$11}}' /proc/net/dev`)
		sleep 2
		traffic_af=(`awk -v eth=$eth -F'[: ]+' '{if ($0 ~eth){print $3,$11}}' /proc/net/dev`)
		#计算速率
		eth_in=$(( (${traffic_af[0]}-${traffic_be[0]})*8/2 ))
		eth_out=$(( (${traffic_af[1]}-${traffic_be[1]})*8/2 ))
		#计算流量峰值
		[[ $eth_in -gt $eth_in_peak ]] && eth_in_peak=$eth_in
		[[ $eth_out -gt $eth_out_peak ]] && eth_out_peak=$eth_out
		#移动光标到2:1
		printf "\033[2;1H"
		#清除当前行
		printf "\033[K"    
		printf "%-20s %-20s\n" "Receive:  $(bit_to_human_readable $eth_in)" "$(bit_to_human_readable $eth_in_peak)"
		#清除当前行
		printf "\033[K"
		printf "%-20s %-20s\n" "Transmit: $(bit_to_human_readable $eth_out)" "$(bit_to_human_readable $eth_out_peak)"
		[[ $clear == true ]] && clear=false
	done
}

#tcp流量概览
tcpTrafficOverview(){
    if ! which tshark > /dev/null;then
        echo "tshark not found,going to install it."
        if check_sys packageManager apt;then
            apt-get -y install tshark
        elif check_sys packageManager yum;then
            yum -y install wireshark
        fi
    fi
 
    local reg=""
    local eth=""
    local nic_arr=(`ip addr | awk  -F'[: @]' '/^[0-9]/{if($3 != "lo"){print $3}}'`)
    local nicLen=${#nic_arr[@]}
    if [[ $nicLen -eq 0 ]]; then
        echo "sorry,I can not detect any network device,please report this issue to author."
        exit 1
    elif [[ $nicLen -eq 1 ]]; then
        eth=$nic_arr
    else
        display_menu nic
        eth=$nic
    fi
 
    echo "please wait for 10s to generate network data..."
    echo
    #当前流量值
    local traffic_be=(`awk -v eth=$eth -F'[: ]+' '{if ($0 ~eth){print $3,$11}}' /proc/net/dev`)
    #tshark监听网络
	tshark -n -s 100 -i $eth -f 'ip' -a duration:10 -R 'tcp' -T fields -e ip.src_host -e tcp.srcport -e ip.dst_host  -e tcp.dstport  -e ip.len | grep -v , > /tmp/tcp.txt
    clear

    #10s后流量值
    local traffic_af=(`awk -v eth=$eth -F'[: ]+' '{if ($0 ~eth){print $3,$11}}' /proc/net/dev`)
    #打印10s平均速率
    local eth_in=$(( (${traffic_af[0]}-${traffic_be[0]})*8/10 ))
    local eth_out=$(( (${traffic_af[1]}-${traffic_be[1]})*8/10 ))
    echo -e "\033[32mnetwork device $eth average traffic in 10s: \033[0m"
    echo "$eth Receive: $(bit_to_human_readable $eth_in)/s"
    echo "$eth Transmit: $(bit_to_human_readable $eth_out)/s"
    echo

    local ipReg=$(ip add show $eth | awk -F'[ +/]' '/inet /{printf $6"|"}' | sed -e 's/|$//' -e 's/^/^(/' -e 's/$/)/')
  

    #统计每个端口在10s内的平均流量
    echo -e "\033[32maverage traffic in 10s base on server port: \033[0m"
	awk -F'\t' -v ipReg=$ipReg '{if ($0 ~ ipReg) {line=$1":"$2}else{line=$3":"$4};sum[line]+=$NF*8/10}END{for (line in sum){printf "%s %d\n",line,sum[line]}}' /tmp/tcp.txt | sort -k 2 -nr | head -n 10 | while read addr len;do
			echo "$addr $(bit_to_human_readable $len)/s"
	done
	
    #echo -ne "\033[11A"
    #echo -ne "\033[50C"
	echo
    echo -e "\033[32maverage traffic in 10s base on client port: \033[0m"
	awk -F'\t' -v ipReg=$ipReg '{if ($0 ~ ipReg) {line=$3":"$4}else{line=$1":"$2};sum[line]+=$NF*8/10}END{for (line in sum){printf "%s %d\n",line,sum[line]}}' /tmp/tcp.txt | sort -k 2 -nr | head -n 10 | while read addr len;do
			echo "$addr $(bit_to_human_readable $len)/s"
	done  
        
    echo

    #统计在10s内占用带宽最大的前10个ip
    echo -e "\033[32mtop 10 ip average traffic in 10s base on server: \033[0m"
	awk -F'\t' -v ipReg=$ipReg '{if ($0 ~ ipReg) {line=$1}else{line=$3};sum[line]+=$NF*8/10}END{for (line in sum){printf "%s %d\n",line,sum[line]}}' /tmp/tcp.txt | sort -k 2 -nr | head -n 10 | while read addr len;do
			echo "$addr $(bit_to_human_readable $len)/s"
	done
    #echo -ne "\033[11A"
    #echo -ne "\033[50C"
	echo
    echo -e "\033[32mtop 10 ip average traffic in 10s base on client: \033[0m"
	awk -F'\t' -v ipReg=$ipReg '{if ($0 ~ ipReg) {line=$3}else{line=$1};sum[line]+=$NF*8/10}END{for (line in sum){printf "%s %d\n",line,sum[line]}}' /tmp/tcp.txt | sort -k 2 -nr | head -n 10 | while read addr len;do
			echo "$addr $(bit_to_human_readable $len)/s"
	done

    echo
    #统计连接状态
    local regSS=$(ip add show $eth | awk -F'[ +/]' '/inet /{printf $6"|"}' | sed -e 's/|$//')
    ss -an | grep -v -E "LISTEN|UNCONN" | grep -E "$regSS" > /tmp/ss
    echo -e "\033[32mconnection state count: \033[0m"
    awk 'NR>1{sum[$(NF-4)]+=1}END{for (state in sum){print state,sum[state]}}' /tmp/ss | sort -k 2 -nr
    echo
    #统计各端口连接状态
    echo -e "\033[32mconnection state count by port base on server: \033[0m"
    awk 'NR>1{sum[$(NF-4),$(NF-1)]+=1}END{for (key in sum){split(key,subkey,SUBSEP);print subkey[1],subkey[2],sum[subkey[1],subkey[2]]}}' /tmp/ss | sort -k 3 -nr | head -n 10   
    echo -ne "\033[11A"
    echo -ne "\033[50C"
    echo -e "\033[32mconnection state count by port base on client: \033[0m"
    awk 'NR>1{sum[$(NF-4),$(NF)]+=1}END{for (key in sum){split(key,subkey,SUBSEP);print subkey[1],subkey[2],sum[subkey[1],subkey[2]]}}' /tmp/ss | sort -k 3 -nr | head -n 10 | awk '{print "\033[50C"$0}'   
    echo   
    #统计状态为ESTAB连接数最多的前10个IP
    echo -e "\033[32mtop 10 ip ESTAB state count: \033[0m"
    cat /tmp/ss | grep ESTAB | awk -F'[: ]+' '{sum[$(NF-2)]+=1}END{for (ip in sum){print ip,sum[ip]}}' | sort -k 2 -nr | head -n 10
    echo
    #统计状态为SYN-RECV连接数最多的前10个IP
    echo -e "\033[32mtop 10 ip SYN-RECV state count: \033[0m"
    cat /tmp/ss | grep -E "$regSS" | grep SYN-RECV | awk -F'[: ]+' '{sum[$(NF-2)]+=1}END{for (ip in sum){print ip,sum[ip]}}' | sort -k 2 -nr | head -n 10
}

#udp流量概览
udpTrafficOverview(){
    if ! which tshark > /dev/null;then
        echo "tshark not found,going to install it."
        if check_sys packageManager apt;then
            apt-get -y install tshark
        elif check_sys packageManager yum;then
            yum -y install wireshark
        fi
    fi
 
    local reg=""
    local eth=""
    local nic_arr=(`ip addr | awk  -F'[: @]' '/^[0-9]/{if($3 != "lo"){print $3}}'`)
    local nicLen=${#nic_arr[@]}
    if [[ $nicLen -eq 0 ]]; then
        echo "sorry,I can not detect any network device,please report this issue to author."
        exit 1
    elif [[ $nicLen -eq 1 ]]; then
        eth=$nic_arr
    else
        display_menu nic
        eth=$nic
    fi
 
    echo "please wait for 10s to generate network data..."
    echo
    #当前流量值
    local traffic_be=(`awk -v eth=$eth -F'[: ]+' '{if ($0 ~eth){print $3,$11}}' /proc/net/dev`)
    #tshark监听网络
	tshark -n -s 100 -i $eth -f 'ip' -a duration:10 -R 'udp' -T fields -e ip.src_host -e udp.srcport -e ip.dst_host  -e udp.dstport  -e ip.len | grep -v , > /tmp/udp.txt
    clear

    #10s后流量值
    local traffic_af=(`awk -v eth=$eth -F'[: ]+' '{if ($0 ~eth){print $3,$11}}' /proc/net/dev`)
    #打印10s平均速率
    local eth_in=$(( (${traffic_af[0]}-${traffic_be[0]})*8/10 ))
    local eth_out=$(( (${traffic_af[1]}-${traffic_be[1]})*8/10 ))
    echo -e "\033[32mnetwork device $eth average traffic in 10s: \033[0m"
    echo "$eth Receive: $(bit_to_human_readable $eth_in)/s"
    echo "$eth Transmit: $(bit_to_human_readable $eth_out)/s"
    echo
	
    local ipReg=$(ip add show $eth | awk -F'[ +/]' '/inet /{printf $6"|"}' | sed -e 's/|$//' -e 's/^/^(/' -e 's/$/)/')
 
    #统计每个端口在10s内的平均流量
    echo -e "\033[32maverage traffic in 10s base on server port: \033[0m"
	awk -F'\t' -v ipReg=$ipReg '{if ($0 ~ ipReg) {line=$1":"$2}else{line=$3":"$4};sum[line]+=$NF*8/10}END{for (line in sum){printf "%s %d\n",line,sum[line]}}' /tmp/udp.txt | sort -k 2 -nr | head -n 10 | while read addr len;do
			echo "$addr $(bit_to_human_readable $len)/s"
	done
	
    #echo -ne "\033[11A"
    #echo -ne "\033[50C"
	echo
    echo -e "\033[32maverage traffic in 10s base on client port: \033[0m"
	awk -F'\t' -v ipReg=$ipReg '{if ($0 ~ ipReg) {line=$3":"$4}else{line=$1":"$2};sum[line]+=$NF*8/10}END{for (line in sum){printf "%s %d\n",line,sum[line]}}' /tmp/udp.txt | sort -k 2 -nr | head -n 10 | while read addr len;do
			echo "$addr $(bit_to_human_readable $len)/s"
	done  
        
    echo

    #统计在10s内占用带宽最大的前10个ip
    echo -e "\033[32mtop 10 ip average traffic in 10s base on server: \033[0m"
	awk -F'\t' -v ipReg=$ipReg '{if ($0 ~ ipReg) {line=$1}else{line=$3};sum[line]+=$NF*8/10}END{for (line in sum){printf "%s %d\n",line,sum[line]}}' /tmp/udp.txt | sort -k 2 -nr | head -n 10 | while read addr len;do
			echo "$addr $(bit_to_human_readable $len)/s"
	done
    #echo -ne "\033[11A"
    #echo -ne "\033[50C"
	echo
    echo -e "\033[32mtop 10 ip average traffic in 10s base on client: \033[0m"
	awk -F'\t' -v ipReg=$ipReg '{if ($0 ~ ipReg) {line=$3}else{line=$1};sum[line]+=$NF*8/10}END{for (line in sum){printf "%s %d\n",line,sum[line]}}' /tmp/udp.txt | sort -k 2 -nr | head -n 10 | while read addr len;do
			echo "$addr $(bit_to_human_readable $len)/s"
	done
}

#http请求统计
httpRequestCount(){
    if ! which tshark > /dev/null;then
        echo "tshark not found,going to install it."
        if check_sys packageManager apt;then
            apt-get -y install tshark
        elif check_sys packageManager yum;then
            yum -y install wireshark
        fi
    fi

    local eth=""
    local nic_arr=(`ip addr | awk  -F'[: @]' '/^[0-9]/{if($3 != "lo"){print $3}}'`)
    local nicLen=${#nic_arr[@]}
    if [[ $nicLen -eq 0 ]]; then
        echo "sorry,I can not detect any network device,please report this issue to author."
        exit 1
    elif [[ $nicLen -eq 1 ]]; then
        eth=$nic_arr
    else
        display_menu nic
        eth=$nic
    fi
 
    echo "please wait for 10s to generate network data..."
    echo
	# tshark抓包
	tshark -n -s 512 -i $eth -a duration:10 -w /tmp/tcp.cap
	# 解析包
	tshark -n -R 'http.host and http.request.uri' -T fields -e http.host -e http.request.uri  -r /tmp/tcp.cap | tr -d '\t' > /tmp/url.txt
	echo -e "\033[32mHTTP Requests Per seconds:\033[0m"
	(( qps=$(wc -l /tmp/url.txt | cut -d ' ' -f1) / 10 ))
	echo "${qps}/s"
	echo
	echo -e "\033[32mTop 10 request url for all requests excluding static resource:\033[0m"
	grep -v -i -E "\.(gif|png|jpg|jpeg|ico|js|swf|css)" /tmp/url.txt | sort | uniq -c | sort -nr | head -n 10
	echo
	echo -e "\033[32mTop 10 request url for all requests excluding static resource and without args:\033[0m"
	grep -v -i -E "\.(gif|png|jpg|jpeg|ico|js|swf|css)" /tmp/url.txt | awk -F'?' '{print $1}' |  sort | uniq -c | sort -nr | head -n 10
	echo
	echo -e "\033[32mTop 10 request url for all requests:\033[0m"
	cat /tmp/url.txt | sort | uniq -c | sort -nr | head -n 10
	echo
	echo -e "\033[32mRespond code count:\033[0m"
	tshark -n -R 'http.response.code' -T fields -e http.response.code -r /tmp/tcp.cap | sort | uniq -c | sort -nr
}

#配置apt yum源
Configure_apt_yum_repository(){
	while true; do
		echo -e "available repository:\n1) mirrors.ustc.edu.cn(recommended)\n2) mirrors.sohu.com\n3) mirrors.aliyun.com\n4) mirrors.163.com\n" 
		read -p "please choose a mirrors(ie.1): " repository
		if [[ "$repository" == "1" ]]; then
		 	repo="ustc"
		 	break

		elif [[ "$repository" == "2" ]]; then
		 	repo="sohu"
		 	break

		elif [[ "$repository" == "3" ]]; then
		 	repo="aliyun"
		 	break	

		elif [[ "$repository" == "4" ]]; then
		 	repo="163"
		 	break	

		else
			echo "input error,please input a number."
		fi			
	done
	
	dateName=$(date +%Y%m%d-%H%M)
	if check_sys sysRelease centos;then
		echo "backing up /etc/yum.repos.d/CentOS-Base.repo to /etc/yum.repos.d/CentOS-Base.repo-${dateName}"
		mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo-${dateName}
		if CentOSVerCheck 5;then
			cp $cur_dir/conf/sources/${repo}-centos5-source.conf /etc/yum.repos.d/CentOS-Base.repo

		elif CentOSVerCheck 6; then
			cp $cur_dir/conf/sources/${repo}-centos6-source.conf /etc/yum.repos.d/CentOS-Base.repo

		elif CentOSVerCheck 7;then
			cp $cur_dir/conf/sources/${repo}-centos7-source.conf /etc/yum.repos.d/CentOS-Base.repo

		else
			echo "Sorry,can not detect your centos version number,or does not support your version."
			read -p "please input your centos version number(ie.6): " versionNumber
			if [[ "$versionNumber" == "5" ]]; then
				cp $cur_dir/conf/sources/${repo}-centos5-source.conf /etc/yum.repos.d/CentOS-Base.repo
			elif [[ "$versionNumber" == "6" ]]; then
				cp $cur_dir/conf/sources/${repo}-centos6-source.conf /etc/yum.repos.d/CentOS-Base.repo
			elif [[ "$versionNumber" == "7" ]]; then
				cp $cur_dir/conf/sources/${repo}-centos7-source.conf /etc/yum.repos.d/CentOS-Base.repo
			else
				echo "your input version number is not supported."
				exit 1
			fi		
		fi	

	elif check_sys sysRelease ubuntu;then
		echo "backing up /etc/apt/sources.list to /etc/apt/sources.list-${dateName}"
		mv /etc/apt/sources.list /etc/apt/sources.list-${dateName}
		versionName=`get_ubuntu_version_name`
		cp $cur_dir/conf/sources/${repo}-ubuntu-source.conf /etc/apt/sources.list
		sed -i "s/versionName/${versionName}/g" /etc/apt/sources.list
		apt-get -y update

	else
		echo "Sorry,only support CentOS and Ubuntu Release now."
		exit 1
	fi

	echo "configure done."
}

#备份设置
Backup_setup(){
	echo "########## file backup setting ##########"
	echo
	while true; do
		echo -e "1) backup files to local\n2) backup file to local and remote\n3) I don't want to backup file\n"
		read -p "please input your choice(ie.1): " fileBackup
		case "$fileBackup" in
			1) file_local_backup_setup;break;;
			2) file_local_backup_setup;file_remote_backup_setup;break;;
			3) break;;
			*) echo "input error,please input a number.";;
		esac
	done

	echo "########## mysql database backup setting ##########"
	echo
	while true; do
		echo -e "1) backup mysql database to local\n2) backup mysql database to local and remote\n3) I don't want to backup mysql\n"
		read -p "please input your choice(ie.1): " mysqlBackup
		case $mysqlBackup in
			1) mysql_local_backup_setup;break;;
			2) mysql_local_backup_setup;mysql_remote_backup_setup;break;;
			3) break;;
			*) echo "input error,please input a number.";;
		esac		
	done

 	rm -f $ini_file
 	touch $ini_file
 	echo > $ini_file

	add_entry_to_ini_file file fileBackupDir "$fileBackupDir"
	add_entry_to_ini_file file excludeRegex "$excludeRegex"
	add_entry_to_ini_file file storageFileDir "$storageFileDir"
	add_entry_to_ini_file file fileLocalExpireDays "$fileLocalExpireDays"

	add_entry_to_ini_file file fileRemoteBackupTool "$fileRemoteBackupTool"
	add_entry_to_ini_file file fileRsyncRemoteAddr "$fileRsyncRemoteAddr"
	add_entry_to_ini_file file fileRsyncPort "$fileRsyncPort"
	add_entry_to_ini_file file fileRsyncUsername "$fileRsyncUsername"
	add_entry_to_ini_file file fileRsyncModuleName "$fileRsyncModuleName"
	add_entry_to_ini_file file fileSshRemoteAddr "$fileSshRemoteAddr"
	add_entry_to_ini_file file fileSshPort "$fileSshPort"
	add_entry_to_ini_file file fileSshUsername "$fileSshUsername"
	add_entry_to_ini_file file fileSshPassword "$fileSshPassword"
	add_entry_to_ini_file file fileRemoteBackupDest "$fileRemoteBackupDest"
	add_entry_to_ini_file file fileFtpServerAddr "$fileFtpServerAddr"
	add_entry_to_ini_file file fileFtpPort "$fileFtpPort"
	add_entry_to_ini_file file fileFtpUsername "$fileFtpUsername"
	add_entry_to_ini_file file fileFtpPassword "$fileFtpPassword"
	add_entry_to_ini_file file rsyncBinPath "$rsyncBinPath"
	add_entry_to_ini_file file fileRemoteExpireDays "$fileRemoteExpireDays"

	add_entry_to_ini_file mysql mysqlBackupTool "$mysqlBackupTool"
	add_entry_to_ini_file mysql mysqlBinDir "$mysqlBinDir"
	add_entry_to_ini_file mysql mysqlAddress "$mysqlAddress"
	add_entry_to_ini_file mysql mysqlPort "$mysqlPort"
	add_entry_to_ini_file mysql mysqlUser "$mysqlUser"
	add_entry_to_ini_file mysql mysqlPass "$mysqlPass"
	add_entry_to_ini_file mysql myCnfLocation "$myCnfLocation"
	add_entry_to_ini_file mysql databaseSelectionPolicy "$databaseSelectionPolicy"
	add_entry_to_ini_file mysql databasesBackup "$databasesBackup"
	add_entry_to_ini_file mysql storageMysqlDir "$storageMysqlDir"
	add_entry_to_ini_file mysql mysqlLocalExpireDays "$mysqlLocalExpireDays"

	add_entry_to_ini_file mysql mysqlRemoteBackupTool "$mysqlRemoteBackupTool"
	add_entry_to_ini_file mysql mysqlRsyncRemoteAddr "$mysqlRsyncRemoteAddr"
	add_entry_to_ini_file mysql mysqlRsyncPort "$mysqlRsyncPort"
	add_entry_to_ini_file mysql mysqlRsyncUsername "$mysqlRsyncUsername"
	add_entry_to_ini_file mysql mysqlRsyncModuleName "$mysqlRsyncModuleName"
	add_entry_to_ini_file mysql mysqlSshRemoteAddr "$mysqlSshRemoteAddr"
	add_entry_to_ini_file mysql mysqlSshPort "$mysqlSshPort"
	add_entry_to_ini_file mysql mysqlSshUsername "$mysqlSshUsername"
	add_entry_to_ini_file mysql mysqlSshPassword "$mysqlSshPassword"
	add_entry_to_ini_file mysql mysqlRemoteBackupDest "$mysqlRemoteBackupDest"
	add_entry_to_ini_file mysql mysqlFtpServerAddr "$mysqlFtpServerAddr"
	add_entry_to_ini_file mysql mysqlFtpPort "$mysqlFtpPort"
	add_entry_to_ini_file mysql mysqlFtpUsername "$mysqlFtpUsername"
	add_entry_to_ini_file mysql mysqlFtpPassword "$mysqlFtpPassword"
	add_entry_to_ini_file mysql rsyncBinPath "$rsyncBinPath"
	add_entry_to_ini_file mysql mysqlRemoteExpireDays "$mysqlRemoteExpireDays"
	
	

	mkdir -p ${backupScriptDir}
	cp ${cur_dir}/backup.ini ${backupScriptDir}
	cp ${cur_dir}/tool/ini_parser.sh ${backupScriptDir}
	cp ${cur_dir}/tool/function.sh ${backupScriptDir}
	cp ${cur_dir}/tool/backup.sh ${backupScriptDir}
	cp ${cur_dir}/tool/dropbox_uploader.sh ${backupScriptDir}
	chmod +x ${backupScriptDir}/backup.sh
	chmod +x ${backupScriptDir}/dropbox_uploader.sh

	if check_sys sysRelease ubuntu || check_sys sysRelease debian;then
		apt-get -y install rsync
		if [[ "$fileBackup" != "3" ]]; then
			! grep -q "backup.sh file" /var/spool/cron/crontabs/root > /dev/null 2>&1 && echo "${fileBackupRate} ${backupScriptDir}/backup.sh file > /dev/null 2>&1"  >> /var/spool/cron/crontabs/root
		fi
		
		if [[ "$mysqlBackup" != "3" ]]; then
			! grep -q "backup.sh mysql" /var/spool/cron/crontabs/root > /dev/null 2>&1 && echo "${mysqlBackupRate} ${backupScriptDir}/backup.sh mysql > /dev/null 2>&1"  >> /var/spool/cron/crontabs/root
		fi

		service cron restart
	elif check_sys sysRelease centos; then
		yum -y install rsync
		if [[ "$fileBackup" != "3" ]]; then
			! grep -q "backup.sh file" /var/spool/cron/root > /dev/null 2>&1 && echo "${fileBackupRate} ${backupScriptDir}/backup.sh file > /dev/null 2>&1"  >> /var/spool/cron/root
		fi
		
		if [[ "$mysqlBackup" != "3" ]]; then
			! grep -q "backup.sh mysql" /var/spool/cron/root > /dev/null 2>&1 && echo "${mysqlBackupRate} ${backupScriptDir}/backup.sh mysql > /dev/null 2>&1"  >> /var/spool/cron/root
		fi
		
		service crond restart
	fi

	#安装工具
	if [[ "$mysqlBackupTool" == "innobackupex" || "$fileBackupTool" == "innobackupex" ]]; then
		Percona_xtrabackup_install
	fi

	if [[ "$mysqlRemoteBackupTool" == "dropbox" || "$fileRemoteBackupTool" == "dropbox" ]]; then
		${backupScriptDir}/dropbox_uploader.sh
	fi

	if [[ "$mysqlRemoteBackupTool" == "rsync"  || "$fileRemoteBackupTool" == "rsync" ]]; then
		echo "$mysqlRsyncPassword" > /etc/rsync.pass
		chmod 600 /etc/rsync.pass
	fi

	if [[ "$mysqlRemoteBackupTool" == "rsync-ssh" || "$fileRemoteBackupTool" == "rsync-ssh" ]]; then
		if check_sys sysRelease ubuntu || check_sys sysRelease debian;then
			apt-get -y install rsync expect

		elif check_sys sysRelease centos; then
			yum -y install rsync expect

		fi
	fi

	if [[ "$mysqlRemoteBackupTool" == "ftp" || "$fileRemoteBackupTool" == "ftp" ]]; then
		if check_sys sysRelease ubuntu || check_sys sysRelease debian;then
			apt-get -y install ftp

		elif check_sys sysRelease centos; then
			yum -y install ftp

		fi
	fi


}

file_local_backup_setup(){
	while true; do
		valid=true
		read -p "please input the directory you'll backup(ie./data1 /data2): " fileBackupDir
		[[ "$fileBackupDir" == "" ]] && valid=false
		for dir in ${fileBackupDir};do
			if [[ ! -d "${dir}" ]];then
				echo "the directory $dir does not exist,or is not a directory,please reinput."
				valid=false
				break
			fi
		done

		$valid && break
	done

	read -p "please input the exclude pattern(support wildcards) for the file backup dir $fileBackupDir(default:none,multiply pattern separated by a space.): " excludeRegex
	
	read -p "please input the directory you'll backup the files to: " storageFileDir
	storageFileDir=`filter_location "$storageFileDir"`
	
	while true; do
		read -p "please input the number of days total to retain the local file backup(ie.3,default:7): " fileLocalExpireDays
		fileLocalExpireDays=${fileLocalExpireDays:=7}
		if [[ "$fileLocalExpireDays" =~ ^[0-9]+$ && "$fileLocalExpireDays" != "0" ]]; then
			break
		else
			echo "input error,please input the number that greater that 0."
		fi
	done

	while true; do
		echo -e "1) every day\n2) every week\n3) custom input cron expression\n"
		read -p "please choose the file backup rate(ie.1,default:1): " fileBackupRate
		fileBackupRate=${fileBackupRate:=1}
		if [[ "$fileBackupRate" == "1" ]];then
			fileBackupRate="01 04 * * *"
			break

		elif [[ "$fileBackupRate" == "2" ]]; then
			fileBackupRate="01 04 01 * *"
			break
		elif [[ "$fileBackupRate" == "3" ]]; then
			while true; do
				read -p "please input cron expression(ie.01 04 * * *): " fileBackupRate
				if verify_cron_exp "$fileBackupRate";then
					break 2
				else
					echo "cron expression is invalid.please reinput."
				fi	
			done
			

		else
			echo "input error,please input a number 1-3."
		fi	
	done
	

	backup_script_dir_setup
}

file_remote_backup_setup(){
	while true; do
		echo -e "backup tool supported:\n1) rsync(with rsync protocol)\n2) rsync(with ssh protocol)\n3) dropbox\n4) ftp\n"
		read -p "please choose a backup tool(ie.1): " fileRemoteBackupTool
		case "$fileRemoteBackupTool" in
			1) fileRemoteBackupTool=rsync;break;;
			2) fileRemoteBackupTool=rsync-ssh;break;;
			3) fileRemoteBackupTool=dropbox;break;;
			4) fileRemoteBackupTool=ftp;break;;
			*) echo "input error,please input a number 1-4."
		esac
	done

	if [[ "$fileRemoteBackupTool" == "rsync" ]]; then
		while true; do
			read -p "please input rsync binary path(default: /usr/bin/rsync): " rsyncBinPath
			rsyncBinPath=${rsyncBinPath:=/usr/bin/rsync}
			if [[ -f "$rsyncBinPath" ]]; then
				break
			else
				echo "file ${rsyncBinPath} not found,please reinput"
			fi	
		done

		ask_not_null_var "please input rsync server remote address(ie.8.8.8.8 www.centos.bz): " fileRsyncRemoteAddr

		while true; do
			read -p "please input rsync server port(default:873): " fileRsyncPort
			fileRsyncPort=${fileRsyncPort:=873}
			if verify_port "$fileRsyncPort";then
				break
			else
				echo "$fileRsyncPort is not a valid port,please reinput."
			fi	
		done

		ask_not_null_var "please input rsync username: " fileRsyncUsername
		ask_not_null_var "please input rsync password: " fileRsyncPassword
		ask_not_null_var "please input rsync module name : " fileRsyncModuleName

	elif [[ "$fileRemoteBackupTool" == "rsync-ssh" ]]; then
		while true; do
			read -p "please input rsync binary path(default: /usr/bin/rsync): " rsyncBinPath
			rsyncBinPath=${rsyncBinPath:=/usr/bin/rsync}
			if [[ -f "$rsyncBinPath" ]]; then
				break
			else
				echo "file ${rsyncBinPath} not found,please reinput"
			fi	
		done

		ask_not_null_var "please input ssh remote address(ie.8.8.8.8 www.centos.bz): " fileSshRemoteAddr

		while true; do
			read -p "please input ssh server port(default:22): " fileSshPort
			fileSshPort=${fileSshPort:=22}
			if verify_port "$fileSshPort";then
				break
			else
				echo "$fileSshPort is not a valid port,please reinput."
			fi	
		done

		ask_not_null_var "please input ssh username(default:root): " fileSshUsername root
		ask_not_null_var "please input ssh password: " fileSshPassword
		read -p "please input the backup destination in the remote server: " fileRemoteBackupDest
		fileRemoteBackupDest=`filter_location "$fileRemoteBackupDest"`


	elif [[ "$fileRemoteBackupTool" == "dropbox" ]]; then
		read -p "please input the backup destination in the dropbox: " fileRemoteBackupDest
		fileRemoteBackupDest=`filter_location "$fileRemoteBackupDest"`

		while true; do
			read -p "please input the number of days total to retain the file backup in the dropbox(ie.3,default:7): " fileRemoteExpireDays
			fileRemoteExpireDays=${fileRemoteExpireDays:=7}
			if [[ "$fileRemoteExpireDays" =~ ^[0-9]+$ && "$fileRemoteExpireDays" != "0" ]]; then
				break
			else
				echo "input error,please input the number that greater that 0."
			fi
		done

	elif [[ "$fileRemoteBackupTool" == "ftp" ]]; then
		ask_not_null_var "please input ftp server address: " fileFtpServerAddr
		while true; do
			read -p "please input ftp server port(default:21): " fileFtpPort
			fileFtpPort=${fileFtpPort:=21}
			if verify_port "$fileFtpPort";then
				break
			else
				echo "$fileFtpPort is not a valid port,please reinput."
			fi	
		done

		ask_not_null_var "please input ftp username: " fileFtpUsername
		ask_not_null_var "please input ftp password: " fileFtpPassword
		read -p "please input the backup destination in the ftp server: " fileRemoteBackupDest
		fileRemoteBackupDest=`filter_location "$fileRemoteBackupDest"`

		while true; do
			read -p "please input the number of days total to retain the file backup in the ftp server(ie.3,default:7): " fileRemoteExpireDays
			fileRemoteExpireDays=${fileRemoteExpireDays:=7}
			if [[ "$fileRemoteExpireDays" =~ ^[0-9]+$ && "$fileRemoteExpireDays" != "0" ]]; then
				break
			else
				echo "input error,please input the number that greater that 0."
			fi
		done		

	fi
	
}

mysql_local_backup_setup(){
	while true; do
		echo -e "supported mysql backup tool: \n1) mysqldump\n2) innobackupex\n"
		read -p "please choose a mysql backup tool(ie.1): " mysqlBackupTool
		case "$mysqlBackupTool" in
			1) mysqlBackupTool=mysqldump;break;;
			2) mysqlBackupTool=innobackupex;break;;
			*) echo "input error,please input a number 1-2."
		esac
	done

	while true;do
		while true; do
			read -p "please input mysql bin directory(default:/usr/local/mysql/bin/): " mysqlBinDir
			mysqlBinDir=${mysqlBinDir:=/usr/local/mysql/bin}
			mysqlBinPath="${mysqlBinDir}"/mysql
			mysqldumpBinPath="${mysqlBinDir}"/mysqldump
			if [[ ! -f "$mysqlBinPath" || ! -f "$mysqldumpBinPath" ]]; then
				echo "mysql or mysqldump not found,please reinput."
			else
				break
			fi	
		done

		read -p "please input mysql address(default:127.0.0.1): " mysqlAddress
		mysqlAddress=${mysqlAddress:=127.0.0.1}

		while true; do
			read -p "please input mysql port number(default:3306): " mysqlPort
			mysqlPort=${mysqlPort:=3306}
			if verify_port "$mysqlPort";then
				break
			else
				echo "the port $mysqlPort is invalid."
			fi	
		done

		read -p "please input mysql user(default:root): " mysqlUser
		mysqlUser=${mysqlUser:=root}

		read -p "please input mysql user $mysqlUser password(default:root): " mysqlPass
		mysqlPass=${mysqlPass:=root}


		if [[ "$mysqlBackupTool" == "innobackupex" ]]; then
			while true; do
				read -p "please input my.cnf location(default:/usr/local/mysql/etc/my.cnf): " myCnfLocation
				myCnfLocation=${myCnfLocation:=/usr/local/mysql/etc/my.cnf}
				if [[ ! -f "$myCnfLocation" ]]; then
					echo "file $myCnfLocation not found,please reinput."
				else
					break
				fi	
			done

		fi	

		if ${mysqlBinPath} -h${mysqlAddress} -P${mysqlPort} -u${mysqlUser} -p${mysqlPass} -e "select 1" > /dev/null 2>&1;then
			break
		else
			echo "${mysqlBinPath} -h${mysqlAddress} -P${mysqlPort} -u${mysqlUser} -p${mysqlPass} -e 'select 1' return error."
			echo "failed to connect mysql server,please reinput." 
		fi	

	done

	databasesName=`${mysqlBinPath} -N -h${mysqlAddress} -P${mysqlPort} -u${mysqlUser} -p${mysqlPass} -e "show databases;" 2>/dev/null | grep -v -E "information_schema|test|performance_schema"`
	if [[ "$databasesName" == "" ]]; then
		echo "there is no database to be backuped."
		exit 1
	fi
	while true; do
		echo "available databases:"
		echo "$databasesName"
		echo
		echo -e "1) include specify databases only\n2) exclude specify databases from all databases.\n3) all databases\n"
		read -p "please choose one database selection policy(ie.1 default:1): " databaseSelectionPolicy
		databaseSelectionPolicy=${databaseSelectionPolicy:=1}
		case "$databaseSelectionPolicy" in
			1) databaseSelectionPolicy=include; break;;
			2) databaseSelectionPolicy=exclude; break;;
			3) databaseSelectionPolicy=all; break;;
			*) echo "input error,please input a number."
		esac
	done


	if [[ "$databaseSelectionPolicy" != "all" ]]; then
		while true; do
			read -p "please input databases(ie.centos ezhttp): " databasesBackup
			if [[ "$databasesBackup" == "" ]]; then
				echo "input can not be empty,please reinput."
			else
				valid=true
				for db in $databasesBackup;do
					if ! if_in_array "$db" "$databasesName";then
						valid=false
						echo "$db database is not found."
					fi	
				done
				$valid && break
			fi	
		done		
	fi

	read -p "please input the directory you'll backup the mysql database to(default:/data/backup/mysql): " storageMysqlDir
	storageMysqlDir=${storageMysqlDir:=/data/backup/mysql}
	storageMysqlDir=`filter_location "$storageMysqlDir"`

	while true; do
		read -p "please input the number of days total to retain the local mysql database backup(ie.3,default:7): " mysqlLocalExpireDays
		mysqlLocalExpireDays=${mysqlLocalExpireDays:=7}
		if [[ "$mysqlLocalExpireDays" =~ ^[0-9]+$ && "$mysqlLocalExpireDays" != "0" ]]; then
			break
		else
			echo "input error,please input the number that greater that 0."
		fi
	done

	while true; do
		echo -e "1) every day\n2) every week\n3) custom input cron expression\n"
		read -p "please choose the mysql backup rate(ie.1,default:1): " mysqlBackupRate
		mysqlBackupRate=${mysqlBackupRate:=1}
		if [[ "$mysqlBackupRate" == "1" ]];then
			mysqlBackupRate="01 04 * * *"
			break

		elif [[ "$mysqlBackupRate" == "2" ]]; then
			mysqlBackupRate="01 04 01 * *"
			break
		elif [[ "$mysqlBackupRate" == "3" ]]; then
			while true; do
				read -p "please input cron expression(ie.01 04 * * *): " mysqlBackupRate
				if verify_cron_exp "$mysqlBackupRate";then
					break 2
				else
					echo "cron expression is invalid.please reinput."
				fi	
			done
			

		else
			echo "input error,please input a number 1-3."
		fi	
	done

	backup_script_dir_setup
}

mysql_remote_backup_setup(){
	while true; do
		echo -e "backup tool supported:\n1) rsync(with rsync protocol)\n2) rsync(with ssh protocol)\n3) dropbox\n4) ftp\n"
		read -p "please choose a backup tool(ie.1): " mysqlRemoteBackupTool
		case "$mysqlRemoteBackupTool" in
			1) mysqlRemoteBackupTool=rsync;break;;
			2) mysqlRemoteBackupTool=rsync-ssh;break;;
			3) mysqlRemoteBackupTool=dropbox;break;;
			4) mysqlRemoteBackupTool=ftp;break;;
			*) echo "input error,please input a number 1-4."
		esac
	done

	if [[ "$mysqlRemoteBackupTool" == "rsync" ]]; then
		while true; do
			read -p "please input rsync binary path(default: /usr/bin/rsync): " rsyncBinPath
			rsyncBinPath=${rsyncBinPath:=/usr/bin/rsync}
			if [[ -f "$rsyncBinPath" ]]; then
				break
			else
				echo "file ${rsyncBinPath} not found,please reinput"
			fi	
		done

		ask_not_null_var "please input rsync server remote address(ie.8.8.8.8 www.centos.bz): " mysqlRsyncRemoteAddr

		while true; do
			read -p "please input rsync server port(default:873): " mysqlRsyncPort
			mysqlRsyncPort=${mysqlRsyncPort:=873}
			if verify_port "$mysqlRsyncPort";then
				break
			else
				echo "$mysqlRsyncPort is not a valid port,please reinput."
			fi	
		done

		ask_not_null_var "please input rsync username: " mysqlRsyncUsername
		ask_not_null_var "please input rsync password: " mysqlRsyncPassword
		ask_not_null_var "please input rsync module name : " mysqlRsyncModuleName

	elif [[ "$mysqlRemoteBackupTool" == "rsync-ssh" ]]; then
		while true; do
			read -p "please input rsync binary path(default: /usr/bin/rsync): " rsyncBinPath
			rsyncBinPath=${rsyncBinPath:=/usr/bin/rsync}
			if [[ -f "$rsyncBinPath" ]]; then
				break
			else
				echo "file ${rsyncBinPath} not found,please reinput"
			fi	
		done

		ask_not_null_var "please input ssh remote address(ie.8.8.8.8 www.centos.bz): " mysqlSshRemoteAddr

		while true; do
			read -p "please input ssh server port(default:22): " mysqlSshPort
			mysqlSshPort=${mysqlSshPort:=22}
			if verify_port "$mysqlSshPort";then
				break
			else
				echo "$mysqlSshPort is not a valid port,please reinput."
			fi	
		done

		ask_not_null_var "please input ssh username(default:root): " mysqlSshUsername root
		ask_not_null_var "please input ssh password: " mysqlSshPassword
		read -p "please input the backup destination in the remote server: " mysqlRemoteBackupDest
		mysqlRemoteBackupDest=`filter_location "$mysqlRemoteBackupDest"`


	elif [[ "$mysqlRemoteBackupTool" == "dropbox" ]]; then
		read -p "please input the backup destination in the dropbox: " mysqlRemoteBackupDest
		mysqlRemoteBackupDest=`filter_location "$mysqlRemoteBackupDest"`

		while true; do
			read -p "please input the number of days total to retain the mysql database backup in the dropbox(ie.3,default:7): " mysqlRemoteExpireDays
			mysqlRemoteExpireDays=${mysqlRemoteExpireDays:=7}
			if [[ "$mysqlRemoteExpireDays" =~ ^[0-9]+$ && "$mysqlRemoteExpireDays" != "0" ]]; then
				break
			else
				echo "input error,please input the number that greater that 0."
			fi
		done

	elif [[ "$mysqlRemoteBackupTool" == "ftp" ]]; then
		ask_not_null_var "please input ftp server address: " mysqlFtpServerAddr
		while true; do
			read -p "please input ftp server port(default:21): " mysqlFtpPort
			mysqlFtpPort=${mysqlFtpPort:=21}
			if verify_port "$mysqlFtpPort";then
				break
			else
				echo "$mysqlFtpPort is not a valid port,please reinput."
			fi	
		done

		ask_not_null_var "please input ftp username: " mysqlFtpUsername
		ask_not_null_var "please input ftp password: " mysqlFtpPassword
		read -p "please input the backup destination in the ftp server: " mysqlRemoteBackupDest
		mysqlRemoteBackupDest=`filter_location "$mysqlRemoteBackupDest"`

		while true; do
			read -p "please input the number of days total to retain the mysql database backup in the ftp server(ie.3,default:7): " mysqlRemoteExpireDays
			mysqlRemoteExpireDays=${mysqlRemoteExpireDays:=7}
			if [[ "$mysqlRemoteExpireDays" =~ ^[0-9]+$ && "$mysqlRemoteExpireDays" != "0" ]]; then
				break
			else
				echo "input error,please input the number that greater that 0."
			fi
		done		

	fi
}

backup_script_dir_setup(){
	if [[ -z $backupScriptDir ]]; then
		read -p "please input the backup script location you'll store(default:/data/sh/) " backupScriptDir
		backupScriptDir=${backupScriptDir:=/data/sh/}
		backupScriptDir=`filter_location "$backupScriptDir"`
		mkdir -p "$backupScriptDir"
	fi	
}


add_entry_to_ini_file(){
	local section="$1"
	local key="$2"
	local val="$3"

	if [[ ! -z "$key" && ! -z "$val" ]]; then
		if grep -q "^\[$section\]$" $ini_file; then
			sed -i "/\[$section\]/a${key}=${val}" $ini_file
			
		else
			sed -i "\$a\[$section]\n${key}=${val}\n" $ini_file
		fi
	fi	
}

#安装rsync server
Install_rsync_server(){
	while true; do
		read -p "please input rsync server port(default:873): " rsyncPort
		rsyncPort=${rsyncPort:=873}
		if verify_port "$rsyncPort";then
			break
		else
			echo "$rsyncPort is not a valid port,please reinput."
		fi	
	done

	ask_not_null_var "please input the allowed address for rsync server(ie.192.168.1.100 192.168.1.0/24 192.168.1.0/255.255.255.0): " allowHost
	ask_not_null_var "please input a module name(ie.webhome): " moduleName
	ask_not_null_var "please input the path for module $moduleName(ie./home): " rsyncPath
	ask_not_null_var "please input the auth user for module $moduleName(ie.ezhttp): " rsyncAuthUser
	ask_not_null_var "please input the auth password for module $moduleName: " rsyncPass

	if check_sys sysRelease ubuntu || check_sys sysRelease debian;then
		apt-get -y install rsync

	elif check_sys sysRelease centos; then
		yum -y install rsync

	fi

	cat > /etc/rsyncd.conf <<EOF
pid file = /var/run/rsyncd.pid   
port = ${rsyncPort}
uid = root   
gid = root   
use chroot = yes 
read only = no 
hosts allow=${allowHost}
hosts deny=*
max connections = 50
timeout = 300
 
[${moduleName}]   
path = ${rsyncPath}
list=yes
ignore errors
auth users = ${rsyncAuthUser}
secrets file = /etc/rsyncd.secrets 
EOF

echo "${rsyncAuthUser}:${rsyncPass}" > /etc/rsyncd.secrets
chmod 600 /etc/rsyncd.secrets
cp ${cur_dir}/conf/general-init.sh /etc/init.d/rsyncd 
chmod +x /etc/init.d/rsyncd
sed -i 's#cmd=.*#cmd="/usr/bin/rsync --daemon --config=/etc/rsyncd.conf"#' /etc/init.d/rsyncd
sed -i 's/processName=.*/processName=rsyncd/' /etc/init.d/rsyncd

/etc/init.d/rsyncd start
boot_start rsyncd

}

# 统计指定进程文件访问
Count_process_file_access(){
	check_command_exist timeout
	check_command_exist strace
	check_command_exist stty
	while true; do
		read -p "please input process pid: " pid
		if [[ "$pid" == "" ]]; then
			echo "pid can not be empty."
			continue
		fi

		if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
		    echo -e "\nGiven Process ID is not a number." >&2
		    continue
		fi

		if [ ! -e /proc/$pid ]; then
		    echo -e "\nThere is no process with $pid as the PID." >&2
		    continue
		fi

		break
	done

	####
	## Initialization
	####

	outputFile=/tmp/out.$RANDOM.$$
	uniqueLinesFile=/tmp/unique.$RANDOM.$$
	finalResults=/tmp/finalOutput.txt.$$

	if [[ "x$PAGER" == "x" ]]; then

	   for currentNeedle in less more cat; do

	      which $currentNeedle >/dev/null 2>&1

	      if [ $? -eq 0 ]; then
	         PAGER=$currentNeedle
	         break;
	      fi

	   done

	  if [[ "x$PAGER" == "x" ]]; then

	     echo "Please set \$PAGER appropriately and re-run" >&2
	     exit 1

	  fi

	fi

	####
	## Tracing
	####

	echo "Tracing command for 30 seconds..."

	timeout 30 strace -e trace=file -fvv -p $pid 2>&1 | egrep -v -e "detached$" -e "interrupt to quit$" | cut -f2 -d \" > $outputFile

	if [ $? -ne 0 ]; then
	   echo -e "\nError performing Trace. Exiting"
	   rm -f $outputFile 2>/dev/null
	   exit 1
	fi

	echo "Trace complete. Preparing Results..."

	####
	## Processing
	####

	sort $outputFile | uniq > $uniqueLinesFile

	echo -e "\n--------  RESULTS --------\n\n  #\t Path " > $finalResults
	echo -e " ---\t-------" >> $finalResults

	while IFS= read -r currentLine; do

	   echo -n $(grep -c "$currentLine" "$outputFile")
	   echo -e "\t$currentLine"

	done < "$uniqueLinesFile" | sort -rn >> $finalResults

	####
	## Presentation
	####

	resultSize=$(wc -l $finalResults | awk '{print $1}')
	currentWindowSize=$(stty size | awk '{print $1}')

	  # We put five literal lines in the file so if we don't have more than that, there were no results
	if [ $resultSize -eq 5 ]; then

	   echo -e "\n\n No Results found!"

	elif [ $resultSize -ge $currentWindowSize ] ; then

	   $PAGER $finalResults

	else

	   cat $finalResults

	fi

	  # Cleanup
	rm -f $uniqueLinesFile $outputFile $finalResults

}

# 安装dotnet和supervisor
Install_dotnet_core(){
	while true;do
		#设置默认路径
		dotnet_default=/usr/local/dotnet
		#nginx安装路径
		read -p "dotnet install location(default:$dotnet_default,leave blank for default): " dotnet_location
		dotnet_location=${dotnet_location:=$dotnet_default}
		dotnet_location=`filter_location "$dotnet_location"`

		if [[ -e $dotnet_location ]]; then
			echo "the location $dotnet_location found,please reinput"
			continue
		else
			break
		fi
	done

	yum -y install libunwind libicu supervisor
	wget "https://go.microsoft.com/fwlink/?LinkID=835019"  -O dotnet.tar.gz
	mkdir -p ${dotnet_location} && tar zxf dotnet.tar.gz -C ${dotnet_location}
	ln -s ${dotnet_location}/dotnet /usr/local/bin

}

# 安装docker
Install_docker(){
	# 检测是否已经安装
	if command_is_exist docker;then
		echo "docker was installed."
		return
	fi

	# docker版本
	local docker_version=$1
	if [[ "$docker_version" == "latest" ]]; then
		docker_version="docker-engine"

	elif [[ "$docker_version" == "" ]];then
		# 输入docker版本
		echo "ubuntu and debian system list versions command: apt-cache madison docker-engine "
		echo "centos system list versions command: yum list docker-engine.x86_64  --showduplicates "
		read -p "please input docker version(ie.docker-engine=1.13.1-0~ubuntu-trusty or docker-engine-1.13.1, default latest): " docker_version
		if [[ "$docker_version" == "" ]]; then
			docker_version=${docker_version:-docker-engine}
		fi
	fi

	# 测试yum.dockerproject.org和mirrors.ustc.edu.cn ping值
	local docker_official_mirror_speed
	local ustc_mirror_speed
	local yum_repository
	local apt_repository

	echo "start ping yum.dockerproject.org and mirrors.ustc.edu.cn to find the faster mirror..."
	docker_official_mirror_speed=$(ping -c4 -nq yum.dockerproject.org | awk -F"/" '/rtt/{print int($5)}')
	docker_official_mirror_speed=${docker_official_mirror_speed:-99999}
	ustc_mirror_speed=$(ping -c4 -nq mirrors.ustc.edu.cn | awk -F"/" '/rtt/{print int($5)}')
	ustc_mirror_speed=${ustc_mirror_speed:-99999}
	echo "docker official mirror ping speed $docker_official_mirror_speed"
	echo "ustc mirror ping speed $ustc_mirror_speed"

	if [[ $ustc_mirror_speed -lt $docker_official_mirror_speed ]]; then
		echo "choose ustc mirror."
		yum_repository='[docker-main]
name=Docker Repository
baseurl=https://mirrors.ustc.edu.cn/docker-yum/repo/centos7/
enabled=1
gpgcheck=1
gpgkey=https://mirrors.ustc.edu.cn/docker-yum/gpg'

		apt_repository="https://mirrors.ustc.edu.cn/docker-apt/repo/"
	else
		echo "choose docker official mirror."
		yum_repository='[docker-main]
name=Docker Repository
baseurl=https://yum.dockerproject.org/repo/main/centos/7/
enabled=1
gpgcheck=1
gpgkey=https://yum.dockerproject.org/gpg'

		apt_repository="https://apt.dockerproject.org/repo/"		
	fi

	# 只支持64位系统
	if ! is_64bit;then
		echo "64 bit system is needed."
		exit 1
	fi

	if check_sys sysRelease centos;then
		# 只支持centos 7
		local version="`VersionGet`"
		local main_ver=${version%%.*}
		if [ $main_ver != "7" ];then
			echo "Error!Must be CentOS 7 OS."
			exit 1
		fi

		# 删除系统自带旧的docker
		yum -y remove docker docker-selinux 

		echo "$yum_repository" > /etc/yum.repos.d/docker.repo
		yum -y install $docker_version
		if [[ $ustc_mirror_speed -lt $docker_official_mirror_speed ]]; then
			sed -i 's|ExecStart=/usr/bin/dockerd|ExecStart=/usr/bin/dockerd --registry-mirror=https://hub-mirror.c.163.com|g' /lib/systemd/system/docker.service
		fi
		systemctl daemon-reload
		systemctl enable docker
		systemctl start docker

	elif check_sys sysRelease ubuntu; then
		apt-get update
		apt-get -y install curl linux-image-extra-$(uname -r) linux-image-extra-virtual
		apt-get -y install apt-transport-https software-properties-common ca-certificates
		curl -fsSL https://yum.dockerproject.org/gpg | sudo apt-key add -
		echo "deb $apt_repository ubuntu-$(lsb_release -cs) main" > /etc/apt/sources.list.d/docker.list
		apt-get update
		apt-get -y install $docker_version

		if [[ $ustc_mirror_speed -lt $docker_official_mirror_speed ]]; then
			echo "DOCKER_OPTS=\"--registry-mirror=https://hub-mirror.c.163.com\"" | tee -a /etc/default/docker
		fi
		update-rc.d -f docker defaults
		service docker restart

	elif check_sys sysRelease debian; then
		apt-get update
		apt-get install curl
		local release=$(lsb_release -cs)
		if [[ $release == "jessie" ]] || [[ $release == "stretch" ]]; then
			apt-get -y install apt-transport-https ca-certificates software-properties-common
		elif [[ $release == "wheezy" ]]; then
			apt-get -y install apt-transport-https ca-certificates python-software-properties
		fi

		curl -fsSL https://yum.dockerproject.org/gpg | apt-key add -

		echo "deb $apt_repository debian-$release main" > /etc/apt/sources.list.d/docker.list
		apt-get update
		apt-get -y install $docker_version

		if [[ $ustc_mirror_speed -lt $docker_official_mirror_speed ]]; then
			echo "DOCKER_OPTS=\"--registry-mirror=https://hub-mirror.c.163.com\"" | tee -a /etc/default/docker
		fi		
		update-rc.d -f docker defaults
		service docker restart

	else
		echo "only support centos,ubuntu,debian."
		exit 1
	fi	
}

# 安装docker compose
Install_docker_compose(){
	local docker_version=$1
	local compose_version=$2
	if [[ "$docker_version" == "" ]];then
		echo "ubuntu and debian system list versions command: apt-cache madison docker-engine "
		echo "centos system list versions command: yum list docker-engine.x86_64  --showduplicates "
		# 输入docker版本
		read -p "please input docker version(ie.docker-engine=1.13.1-0~ubuntu-trusty or docker-engine-1.13.1, default latest): " docker_version
		docker_version=${docker_version:-latest}
	fi

	if [[ "$compose_version" == "" ]];then
		# 输入docker compose版本
		echo "available compose version: https://github.com/docker/compose/releases"
		read -p "please input docker compose version(ie.1.10.1 default 1.10.1): " compose_version
		compose_version=${compose_version:-1.10.1}
	fi

	# 检测docker是否已经安装
	Install_docker $docker_version
	local proxy
	# 使用代理
	echo "testing the network..."
	if [[ $(ping -c4 -nq www.google.com | awk -F"/" '/rtt/{print int($5)}') == "" ]]; then
		echo "There is a networking issue,use the proxy..."
		proxy="-x us.centos.bz:31281"
	fi	
	curl -L $proxy "https://github.com/docker/compose/releases/download/$compose_version/docker-compose-Linux-x86_64" -o /usr/local/bin/docker-compose
	chmod +x /usr/local/bin/docker-compose
	docker-compose --version
}

# 安装shadowsocks
install_shadowsocks(){
    if command_is_exist ssserver; then
        echo "shadowsocks had been installed in your server."
        return
    fi

    if ! command_is_exist pip; then
        if check_sys packageManager apt;then
            apt-get update
            apt-get -y install python-pip
        elif check_sys packageManager yum;then
            yum -y install python-pip
        fi      
    fi

    pip install shadowsocks

    if command_is_exist ssserver; then
        echo "installing shadowsocks done."
    else
        echo "failed to install shadowsocks."
    fi
}

# 列出目前运行着的shadowsocks
list_current_running_shadowsocks(){
    ps aux | grep [s]sserver | awk 'BEGIN{printf "%-8s %-8s %s\n------------------------\n","PID","PORT","PASSWORD"}{printf "%-8s %-8s %s\n",$2,$14,$16}'
}

# 启动一个新的shadowsocks进程
start_a_new_shadowsocks_process(){
    local server_port
    local password

    while true; do
        read -p "please input a server port number:(ie.8585) " server_port
        if ! verify_port $server_port;then
            echo "$server_port is invalid."
            continue
        fi

        if [[ $(ss -ltn | awk '{print $4}' | grep -o -E [0-9]+ | sort -u | grep $server_port) != "" ]];then
            echo "there is another process listenning on the $server_port port,please choose another."
            continue
        fi
        break
    done

    while true; do
        read -p "please input a password: " password
        if [[ $password == "" ]];then
            echo "password can not be empty."
            continue
        fi  
        break
    done

    echo "start a new shadowsocks process..."
    local start_cmd="ssserver -p $server_port -k $password --pid-file /var/run/shadowsocks-$server_port.pid -d start"
    if $start_cmd;then
        echo "start shadowsocks process successfully."
    else
        echo "failed to start shadowsocks."
    fi

    if ! grep -q -- "$start_cmd" /etc/rc.local;then
        sed -i "\$i$start_cmd" /etc/rc.local
    fi
}

# 卸载shadowsocks
uninstall_a_shadowsocks_process(){
    local pid
    echo "current running shadowsocks:"
    list_current_running_shadowsocks
    while true; do
        read -p "please input shadowsocks's pid to uninstall: " pid
        if [[ $(ps aux | grep [ss]server | awk '{print $2}' | grep $pid) == "" ]];then
            echo "shadowsocks pid $pid not found."
            continue
        fi
        break
    done

    local server_port=$(ps aux | grep [s]sserver | awk -v pid=$pid '$2 == pid {print $14}')
    kill $pid
    sleep 2
    if [[ $(ps aux | grep [ss]server | awk '{print $2}' | grep $pid) == "" ]];then
        echo "kill shadowsocks successfully."
    fi
    
    sed -i "/ssserver -p $server_port/d" /etc/rc.local
}

# 部署shadowsocks
Deploy_shadowsocks(){
    while true; do
        echo -e "1) install shadowsocks.\n2) list current running shadowsocks.\n3) start a new shadowsocks process.\n4) uninstall a shadowsocks.\n5) exit the script.\n" 
        read -p "please input your select(ie 1): " select
        case  $select in
            1) install_shadowsocks;;
            2) list_current_running_shadowsocks;;
            3) start_a_new_shadowsocks_process;;
            4) uninstall_a_shadowsocks_process;;
            5) exit;;
            *) echo "input error,please input a number.";;
        esac
    done
}

# 安装Jexus
Install_jexus(){
	local jexus_version
	while true; do
		read -p "please input jexus version(default 5.8.2): " jexus_version
		if [[ "$jexus_version" == "" ]];then
			jexus_version="5.8.2"
		fi
		
		if [[ ! "$jexus_version" =~ [0-9]\.[0-9]\.[0-9] ]]; then
			echo "wrong version,valid version is x.x.x"
			continue
		fi
		echo "input version $jexus_version"
		break

	done
	if CentOSVerCheck 6;then
		yum -y install yum-utils
		rpm --import "http://keyserver.ubuntu.com/pks/lookup?op=get&search=0x3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF"
		yum-config-manager --add-repo ftp://150.36x.cn/mono/repo-centos6/repo/centos6/
		yum -y install mono-devel mono-complete

	elif CentOSVerCheck 7; then
		yum -y install yum-utils
		rpm --import "http://keyserver.ubuntu.com/pks/lookup?op=get&search=0x3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF"
		yum-config-manager --add-repo ftp://150.36x.cn/mono/repo-centos7/repo/centos7/
		yum -y install mono-devel mono-complete

	else
		echo "your system is not supported yet."
		exit
	fi

	cd /tmp
	rm -rf jexus*
	wget ftp://150.36x.cn/mono/jexus/jexus-$jexus_version.tar.gz
	if [[ ! -f $jexus_version.tar.gz ]]; then
		wget http://www.linuxdot.net/down/jexus-$jexus_version.tar.gz
	fi
	tar -zxvf jexus-$jexus_version.tar.gz 
	cd jexus-$jexus_version 
	sudo ./install
	/usr/jexus/jws start
	echo "install complete."

}

#工具设置
tools_setting(){
	clear
	display_menu tools
	if [ "$tools" == "Back_to_main_menu" ];then
		clear
		pre_setting
	else
		eval $tools
	fi	

}
