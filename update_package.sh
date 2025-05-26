#!/bin/bash

apt_install_cmd="sudo apt --assume-yes --no-install-recommends --allow-downgrades install"
apt_remove_cmd="sudo apt --assume-yes remove"
progress_prefix=progress:
#20210610
remove_same_ver(){
	installed_ver=$(dpkg -s asiair|grep -w Version|cut -f2 -d:)
	if [ -z "$installed_ver" ];then 
		echo not installed
	else
		echo old:"$installed_ver"
		echo new:"$deb_ver" 
		if [ "$deb_ver" = "$installed_ver" ];then 
			echo ver is same, remove	
			$apt_remove_cmd asiair
		fi
	fi
}

replace_file()
{
	if [ $# -lt 2 ];then
		echo "error, too few args"
		return 0
	fi
	local src_fullname=$1
	if [ -f ${src_fullname} ];then
		local dst_fullname=$2
		cmp ${src_fullname} ${dst_fullname} 2>&1
		if [ $? -ne 0 ];then		
			sudo mv ${src_fullname} ${dst_fullname} 2>&1
			sync
			date
			echo ${dst_fullname} synced
			return 1
		else
			echo ${dst_fullname} not change
		fi
	else
		echo ${src_fullname} not exist
	fi    
	return 0
}

replace_file_reboot()
{
	replace_file "$1" "$2"
	replace_ret=$?
	let need_reboot+=$replace_ret
	echo need_reboot=$need_reboot
	return $replace_ret
}

install_deb(){

date
echo "update pre deb>"

#//nginx: [emerg] chown("/var/www/client_body_temp", 65534) failed (30: Read-only file system)
#update时ln -s
test -d /tmp/www||(sudo mkdir -p /tmp/www;sudo chmod 777 /tmp/www)

sudo killall -9 nginx
ls -l /var/www|grep -w /tmp/www&&echo link of /var/www is ok ||(echo make link of /var/www;sudo rm -r /var/www/;sudo ln -s /tmp/www/ /var/www)
replace_file "$script_path/others/nginx.conf" "/etc/nginx/nginx.conf"
replace_file "$script_path/others/dnsmasq.conf" "/etc/dnsmasq.conf"

remove_same_ver

#20231207 杨哥，这个包下次更新的时候要安装一下，要先检查有没有busybox-syslogd，有的化要卸载掉sudo apt remove busybox-syslogd
$apt_remove_cmd busybox-syslogd

#$apt_install_cmd $script_path/deb/*.deb 2>&1
install_ret=$($apt_install_cmd $script_path/deb/*.deb 2>&1)
echo install result:
echo "$install_ret"
echo "$install_ret"|grep "dpkg was interrupted, you must manually run 'sudo dpkg --configure -a' to correct the problem"
if [ $? -eq 0 ];then
	echo "dpkg fix>"
	dpkg_conf_ret=$(sudo dpkg --configure -a 2>&1)

	date
	echo dpkg fix result:
	echo "$dpkg_conf_ret"
#dpkg: error: parsing file '/var/lib/dpkg/updates/0005' near line 12 package 'asiair':
#end of file before value of field 'Break' (missing final newline)
	echo "$dpkg_conf_ret"|grep "parsing file '/var/lib/dpkg/updates/"
	if [ $? -eq 0 ];then
		sudo rm /var/lib/dpkg/updates/*
		echo "remove var updates, repeat fix>"
		sudo dpkg --configure -a 2>&1
	else
		echo "dpkg fix ok"
	fi
 
	echo "dpkg fixed, reinstall>"
	$apt_install_cmd $script_path/deb/*.deb 2>&1
else	
	echo "skip dpkg fix"

	installed_ver=$(dpkg -s asiair|grep -w Version|cut -f2 -d:)
	echo installed_ver=$installed_ver
	if [ "$deb_ver" = "$installed_ver" ];then
		echo asiair is installed
	else
		echo error, asiair NOT installed
	fi
	
fi	


#20200228有依赖关系必须要按一定的顺序安装，一起安装apt install 命令太长又怕有问题
#$apt_install_cmd $script_path/deb/indi-y_armhf.deb
#$apt_install_cmd $script_path/deb/indi_eqmod-y_armhf.deb
#$apt_install_cmd $script_path/deb/indi_starbook-y_armhf.deb
#$apt_install_cmd $script_path/deb/indi_stargo-y_armhf.deb
#$apt_install_cmd $script_path/deb/libfuse2_2.9.9-1_armhf.deb $script_path/deb/fuse_2.9.9-1_armhf.deb $script_path/deb/exfat-fuse_1.3.0-1_armhf.deb
#$apt_install_cmd $script_path/deb/ntfs-3g_2017.3.23AR.3-3_armhf.deb $script_path/deb/libntfs-3g883_2017.3.23AR.3-3_armhf.deb
#$apt_install_cmd $script_path/deb/python3-ephem_3.7.6.0-7+b1_armhf.deb
#$apt_install_cmd $script_path/deb/libgphoto2-port12-2.5.24-3_armhf.deb $script_path/deb/libgphoto2-6_2.5.24-1_armhf.deb $script_path/deb/libgphoto2-dev_2.5.24-1_armhf.deb
#$apt_install_cmd $script_path/deb/nginx_1.11.8_armhf.deb
#$apt_install_cmd $script_path/deb/asiair_armhf.deb

#要更新下动态库，比如libASICamera2.so
#20241029 经纬仪固件更新要运行imager，防止找不到libzalgorithm.so
date
echo "ldconfig 0"
sudo ldconfig
}

get_latest_log()
{
max=0
log_file=$log_path$1
max_file=$log_file.txt
for f in $(find $log_path -wholename "${log_file}*.txt"); do 
	re="([0-9]+).txt"
	if [[ $f =~ ($re) ]];then
	inter=${BASH_REMATCH[2]}
		if [ $inter -gt $max ];then
			max_file=$f
			max=$inter
		fi
	fi

#echo "$f: $inter"

done
}

move_log()
{
	if [ $# -lt 1 ];then
        echo "error, too few args"
        return
	fi
	log_files=${log_path}$1*.txt
	if ! ls ${log_files} > /dev/null;then
        echo no log $1;
        return
	fi
	get_latest_log $1
	echo $1: max=$max, max_file=$max_file
	mv $max_file $folder
	rm ${log_files}
}

remove_conf_func()
{
if [ $remove_conf -ne 1 ];then
	return
fi

echo remove all station ssid
/home/pi/ASIAIR/bin/network.sh remove_all

echo remove all xml json txt
rm /home/pi/.ZWO/*.xml
rm /home/pi/.ZWO/*.json
rm /home/pi/.ZWO/*.txt
}

print_progress(){
	echo ${progress_prefix}"$1"
}

cp_mount_fw()
{
	echo "sync mount fw to etc >"					
	replace_file "$mount_fw_path" "/etc/zwo/esptool/espfirmware/main.bin"
}

update_mount(){
#./AM_Test -v|grep Version|cut -f2 -d:
#1.2.6

#./AM_Test -f /home/pi/main.bin -u
#constructor called!
#the filepath is : /tmp/zwo/log
#the log file path is : /tmp/zwo/log/amsdk
#failed to create directory:File exists
#the log is : /tmp/zwo/log/amsdk/amsdk.log
#/home/pi/main.bin
#==file:/home/pi/main.bin==
#destructor called!

#./AM_Test -v|grep Version|cut -f2 -d:
#1.0.2

#strings update/main\(1\).bin| grep -E '^[0-9]+\.[0-9]+\.[0-9]+$'
#1.2.7

#print_progress "hahaha"
#	mount_fw_path=$script_path/others/main.bin

# 3-11_11:51:15.195247 [MainArgHandle]cam_sensor_model=462
# 3-11_11:51:15.195467 [MainArgHandle]device_model_short=S50
#main_S50_1.6.5.bin

#	mount_fw_pre=main_${device_model_short}_
	mount_fw_pre=Seestar
#	if [ $is_s30 -eq 1 ]; then
#		mount_fw_pre=S30_Seestar
#	fi
	echo mount_fw_pre=${mount_fw_pre}
	mount_fw_path=$(ls -t $script_path/others/${mount_fw_pre}*.bin|head -1)
	mount_fw_updater=${daemon_path}AM_Test
	echo "mount_fw_path=${mount_fw_path}, mount_fw_updater=${mount_fw_updater}"
	if [ -f "$mount_fw_path" ] && [ -f "$mount_fw_updater" ];then

		chmod +x $mount_fw_updater
		new_ver=$(strings $mount_fw_path| grep -E '^[0-9]+\.[0-9]+\.[0-9a-z]+$')
		cur_ver=$($mount_fw_updater -v|grep Version|cut -f2 -d:)
		echo cur_ver=$cur_ver, new_ver=$new_ver
		if [ $cur_ver = $new_ver ];then
			echo "same version, skip mount update"
			cp_mount_fw
		else	
			date
			echo "mount go home>"
			mount_log=${script_path}update_out_mount
			$mount_fw_updater -h > ${mount_log} 2>&1
			date
			echo "mount updating>"
			chmod +x $daemon_path$imager_exec
			$daemon_path$imager_exec -b "$mount_fw_path" >> ${mount_log} 2>&1	
			mount_update_ret=$?
			date
			echo mount_update_ret=$mount_update_ret
			if [ $mount_update_ret -eq 0 ];then
				echo "mount update success"
				arg_gohome_horiz='-H'
				export arg_gohome_horiz
			else
				echo "mount update failed"
			fi	
			
			cnt=0
			while [ $cnt -lt 5 ]
			do
				$mount_fw_updater -v|grep Version
				if [ $? -eq 0 ];then
					date			
					echo get ver ok
					cp_mount_fw
					break
				fi	
				date
				echo "waiting version>"
				sleep 1
				cnt=$[$cnt+1]
			done
		fi
	else
		echo "lack of mount update file"
	fi
}

play_sound()
{	
	if [ -z "$1" ];then
		echo "play_sound: arg is empty"
		return
	fi

	${play_sound_exec} -p $1 2>&1
}


#pi (cm)4k肯定要装
bord_model=$(cat /proc/device-tree/model)
echo $bord_model|grep 'ZWO SeeStar'
if [ $? -eq 0 ];then
	echo "this is SeeStar"
else	
	echo "error, not SeeStar, exit "
	
	#必须放后面，否则文件直接就结束了eof
	echo $bord_model
	exit 1
fi

need_reboot=0
#echo opt_num=$#
remove_conf=0
autodowngrade=0
while (( "$#" )); do 
#	echo $1 
	if [ $1 = "--remove-conf" ];then
		remove_conf=1		
	fi
	
	if [ $1 = "--autodowngrade" ];then
		autodowngrade=1		
	fi
	shift 
done
echo remove_conf=$remove_conf autodowngrade=$autodowngrade

script_path=$(dirname $(realpath $0))
script_path=$script_path"/"
echo $script_path

source /home/pi/ASIAIR/config

deb_ver=$(dpkg --info  $script_path/deb/asiair_armhf.deb |grep -w Version|cut -f2 -d:)
fac_log_path=/home/pi/factory
if [ -d "$fac_log_path" ];then
	fac_log_size=$(du -sm "$fac_log_path"|cut -f1)
	echo fac_log_size=$fac_log_size
	if [ $fac_log_size -gt 80 ];then
		echo remove factory log
		sudo rm -r "$fac_log_path"
	else
		echo keep factory log
	fi
else
	echo $fac_log_path not exist
fi

play_sound_exec=${script_path}/others/$updater_exec
chmod +x ${play_sound_exec}

echo "stop imager and guider>"

#kill daemon first, avoid imager and guider to be restarted
ps -ef|grep $daemon_exec|grep -v grep|awk '$1=="pi"{print $2}'|xargs sudo kill -9
sudo killall -2 $guider_exec
sudo killall -2 $imager_exec
sudo killall indiserver

flash_pled_exec=${script_path}/others/flash_power_led
chmod +x ${flash_pled_exec}
${flash_pled_exec} 3 333 > /dev/null 2>&1 &
#flash_pid=$!

#cat /home/pi/.ZWO/ASIAIR_imager.xml |grep lang_name|grep '>0<'

if [ -z $sound_done ];then
	echo "play sound 0>"
	play_sound 30
else
	echo "not play sound 0"
	unset sound_done
fi


log_path=$(cat /home/pi/ASIAIR/config |grep -w log_path|cut -f2 -d"=")

date
echo "$script_path"root/cp-files.sh""
print_progress "copy file"

readonly=$(mount|grep -w /|grep -w rw)
if [ -z "$readonly" ];then
sudo mount -o remount,rw /
fi

#20210916
echo "check RTC"
timedatectl |grep 'RTC in local TZ'|grep -w yes&&echo "RTC already local TZ" ||(echo "set RTC local TZ";sudo timedatectl set-local-rtc 1)

date
echo "sync0>"
sync
date
echo "sync0<"

install_deb

date
echo "sync>"
print_progress "write disk"
sync
date
echo "sync<"

source /home/pi/ASIAIR/config



cnt=0
while [ 1 ]
do
	guider_running=$(ps -ef|grep -w $guider_exec|grep -v grep|awk '{print $2}')	
	
	if [ -z "$guider_running" ];then
		date
		echo "guider is stopped"
		break
	else
	
		echo "guider is running"
		if [ $cnt -gt 8 ];then
		date
		echo "guider is force stopped"
		sudo killall $guider_exec
		fi
	fi
sleep 1
cnt=$[$cnt+1]
done


cnt=0
while [ 1 ]
do
	imager_running=$(ps -ef|grep -w $imager_exec|grep -v grep|awk '{print $2}')	
	
	if [ -z "$imager_running" ];then
		date
		echo "imager is stopped"
		break
	else
		
		echo "imager is running"
		if [ $cnt -gt 8 ];then
		date
		echo "imager is force stopped"
		sudo killall $imager_exec
		fi	
	fi
sleep 1
cnt=$[$cnt+1]
done

#20201208放到一个文件夹里，用于上传日志
folder_dir=$script_path"old_log/"

#20210720不删除老的，可能降级后升级，要保留两份
#rm -r $folder_dir
folder=$folder_dir$(date +%y%m%d-%H%M%S)
mkdir -p $folder

echo "backup imager and guider log->$folder"

move_log log_imager
move_log log_guider
move_log log_aux_imager

chmod +x $updater_path$updater_exec
model_info_ret=$($updater_path$updater_exec -s 2>&1)
device_model_short=$(echo "$model_info_ret"|grep device_model_short|cut -f2 -d=)
echo device_model_short=$device_model_short
model_dir="$script_path/others/${device_model_short}"
	
is_s30=0
if [ -n "${device_model_short}" ] && [[ "${device_model_short}" == S30 ]]; then
	is_s30=1
fi

is_need_update_external_libs=0
if [ -n "${device_model_short}" ];then
	if [[ "${device_model_short}" == S30 ]] || [[ "${device_model_short}" == S50 ]];then
		is_need_update_external_libs=1
	fi
fi

#必须放这里，不能放函数里，否则顺序不对
print_progress "update mount FW"
update_mount

date
echo "restart imager and guider>"
print_progress "restart server"

echo "kill updater>"
sudo killall -2 $updater_exec

echo need_reboot=$need_reboot

sudo rm /usr/bin/zwo_deleteStarsTool
######################
#pwrled_gpio.ko
#will crash
#		sudo rmmod pwrled_gpio 2>&1
#		sudo insmod ${dst_fullname} 2>&1
replace_file "$script_path/others/pwrled_gpio.ko" "/usr/lib/modules/4.19.111/kernel/drivers/misc/pwrled_gpio.ko"


#imx462_CMK-OT1234-FV0_M00-2MP-F00.xml  
replace_file "$script_path/others/imx462_CMK-OT1234-FV0_M00-2MP-F00.xml" "/etc/zwo/imx462_CMK-OT1234-FV0_M00-2MP-F00.xml"


replace_file_reboot "${model_dir}/eaf.ko" "/lib/modules/4.19.111/kernel/drivers/misc/eaf.ko"

#sudo cp video_rkcif.ko /lib/modules/4.19.111/kernel/drivers/media/platform/rockchip/cif/

replace_file_reboot "${model_dir}/video_rkcif.ko" "/lib/modules/4.19.111/kernel/drivers/media/platform/rockchip/cif/video_rkcif.ko"


# imx462.ko会重启，必须放最后！！！
#20231122用replace_file

#./zwoair_updater -s 2>&1|grep cam_sensor_model|cut -f2 -d=
#462
cam_sensor_model=$(echo "$model_info_ret"|grep cam_sensor_model|cut -f2 -d=)
if [ -n "${cam_sensor_model}" ];then
	echo cam_sensor_model=${cam_sensor_model}
	replace_file_reboot "${model_dir}/imx${cam_sensor_model}.ko" "/lib/modules/4.19.111/kernel/drivers/media/i2c/imx${cam_sensor_model}.ko"
else
	echo unknown cam_sensor_model
fi

if [ $is_s30 -eq 1 ]; then

	replace_file_reboot "${model_dir}/gc2083.ko" "/lib/modules/4.19.111/kernel/drivers/media/i2c/gc2083.ko"

	#sudo cp S30_video_rkisp.ko /lib/modules/4.19.111/kernel/drivers/media/platform/rockchip/isp/video_rkisp.ko
	replace_file_reboot "${model_dir}/video_rkisp.ko" "/lib/modules/4.19.111/kernel/drivers/media/platform/rockchip/isp/video_rkisp.ko"

#-rwxr-xr-x 1 root root 2760 Jun  5 17:39 /etc/rc.local
#替换后是这样
#-rwxr-xr-x 1 pi pi 2548 Jul 10 14:25 /etc/rc.local
	replace_file_reboot "${model_dir}/rc.local" "/etc/rc.local"
#mv后owner会跟着变
	if [ $? -eq 1 ]; then
		sudo chmod +x /etc/rc.local
		echo "chmod rc.local"
	fi

	replace_file_reboot "$script_path/others/zwo-beeper.ko" "/lib/modules/4.19.111/kernel/drivers/misc/zwo-beeper.ko"
	
	replace_file "${model_dir}/librkaiq.so" "/usr/lib/librkaiq.so"
	replace_file_reboot "${model_dir}/video_rkispp.ko" "/lib/modules/4.19.111/kernel/drivers/media/platform/rockchip/ispp/video_rkispp.ko"

	replace_file_reboot "${model_dir}/ak09915.ko" "/lib/modules/4.19.111/kernel/drivers/iio/magnetometer/ak09915.ko"

	replace_file "${model_dir}/pwm_gpio.ko" "/lib/modules/4.19.111/kernel/drivers/misc/pwm_gpio.ko"		

	replace_file_reboot "${model_dir}/inv-mpu-iio.ko" "/lib/modules/4.19.111/kernel/drivers/iio/imu/inv_mpu/inv-mpu-iio.ko"

	replace_file "${model_dir}/test_asiair_file.sh" "/etc/zwo/test_asiair_file.sh"
	if [ $? -eq 1 ]; then
		sudo chmod +x "/etc/zwo/test_asiair_file.sh"
		echo "chmod test_asiair_file.sh"
	fi
else
	echo "not s30, not update some files"
fi

if [ $is_need_update_external_libs -eq 1 ];then
	replace_file "$script_path/others/libv4l/libv4l1.so.0.0.0" "/usr/lib/arm-linux-gnueabihf/libv4l1.so.0.0.0"
	replace_file "$script_path/others/libv4l/libv4l2rds.so.0.0.0" "/usr/lib/arm-linux-gnueabihf/libv4l2rds.so.0.0.0"
	replace_file "$script_path/others/libv4l/libv4l2.so.0.0.0" "/usr/lib/arm-linux-gnueabihf/libv4l2.so.0.0.0"
	replace_file "$script_path/others/libv4l/libv4lconvert.so.0.0.0" "/usr/lib/arm-linux-gnueabihf/libv4lconvert.so.0.0.0"
	replace_file "$script_path/others/libv4l/libv4l-mplane.so" "/usr/lib/arm-linux-gnueabihf/libv4l/plugins/libv4l-mplane.so"
	replace_file "$script_path/others/libv4l/v4l1compat.so" "/usr/lib/arm-linux-gnueabihf/libv4l/v4l1compat.so"
	replace_file "$script_path/others/libv4l/v4l2convert.so" "/usr/lib/arm-linux-gnueabihf/libv4l/v4l2convert.so"
fi

if [ -n "${device_model_short}" ] && [[ "${device_model_short}" == S30P ]]; then
	replace_file "${model_dir}/libeasymedia.so.1" "/lib/libeasymedia.so.1"
	replace_file_reboot "${model_dir}/imx586.ko" "/lib/modules/4.19.111/kernel/drivers/media/i2c/imx586.ko"	
fi

if [ -n "${device_model_short}" ];then
	if [[ "${device_model_short}" == S30 ]] || [[ "${device_model_short}" == S30P ]];then
		replace_file "$script_path/others/aplay" "/usr/bin/aplay"
		if [ $? -eq 1 ];then
			sudo chmod +x /usr/bin/aplay
			echo "chmod aplay"
		fi
	fi
fi

old_etc_owner=$(ls -ld /etc|awk '{print $3,$4}')
old_NPU_init_perm=$(ls /etc/init.d/S05NPU_init -l|awk '{print $1}')
while read -r line
do
#	echo "$line"
	ls -ld "$line" |awk '{print $3,$4}'|grep 'root root' > /dev/null
	if [ $? -ne 0 ];then
		echo set owner $line
		sudo chown root:root "$line"
	fi
done < <(find $script_path/others/npu/to_sync -type d)

sudo chmod +x $script_path/others/npu/to_sync/etc/init.d/S05NPU_init
sudo chmod +x $script_path/others/npu/to_sync/etc/init.d/S60NPU_init

sudo rsync -a --progress $script_path/others/npu/to_sync/ /
echo "sync>"
sync
date

new_etc_owner=$(ls -ld /etc|awk '{print $3,$4}')

if [ "$old_etc_owner" != "$new_etc_owner" ];then
	need_reboot=1
	echo "etc owner change: $old_etc_owner to $new_etc_owner"
else
	echo etc owner remain same: $new_etc_owner
fi

new_NPU_init_perm=$(ls /etc/init.d/S05NPU_init -l|awk '{print $1}')

if [ "$old_NPU_init_perm" != "$new_NPU_init_perm" ];then
	need_reboot=1
	echo "NPU_init_perm change: $old_NPU_init_perm to $new_NPU_init_perm"
else
	echo NPU_init_perm remain same: $new_NPU_init_perm
fi

#20240109 others/npu/to_sync里有动态库，可能要更新下?
echo "ldconfig 1"
sudo ldconfig

###########更新S30内核##############
#更新方法：”sudo updateEngine --image_url=/tmp/update.img --savepath=/boot/Image/update.img --misc=update --partition=0x080000 --reboot &“
#更新后内核版本：”Linux SeeStar 4.19.111 #1 SMP PREEMPT Fri Sep 6 10:20:45 CST 2024 armv7l GNU/Linux“
if [ $is_s30 -eq 1 ]; then
	uname_ver=$(uname -v)
	date_num=$(date -d "$(echo $uname_ver | awk '{print $5, $6, $9}')" +"%Y%m%d")
	echo uname_ver=$uname_ver,date_num=$date_num
	if [[ "$date_num" < 20200000 ]];then
		echo "img date is valid"
	elif [[ "$date_num" < 20241121 ]];then
		img_path=${model_dir}/update.img
		if [ -f "${img_path}" ];then
			echo "is old, update img, sync>"
			#20250117 解决/etc权限改变？
			sync
			echo "sync<"
		#	play_sound 34
			sudo updateEngine --image_url=${img_path} --savepath=/boot/Image/update.img --misc=update --partition=0x280000 --reboot
		else
			echo 'update.img not exist'
		fi
	else
		echo 'is new, not update img'
	fi
else
	echo 'not update img'
fi

###########check reboot##########
if [ $need_reboot -gt 0 ];then	
	echo remove conf before reboot
	chmod +x $daemon_path$imager_exec
	$daemon_path$imager_exec -Uq > ${script_path}update_out_remove_conf 2>&1
	
	echo start reboot
	play_sound 34
	${daemon_path}auto_shutdown.sh reboot
else
	echo not reboot
fi
#######################

remove_conf_func

if [ $autodowngrade -eq 1 ];then
	echo "not start imager and guider"
else
	arg_fw_update='-U'
	export arg_fw_update	
	chmod +x $daemon_path$daemon_exec
	$daemon_path$daemon_exec > /dev/null 2>&1 &
	date
	echo "imager and guider is restarted"
fi




while [ 1 ]
do
	updater_running=$(ps -ef|grep -w $updater_exec|grep -v grep|awk '{print $2}')	
	
	if [ -z "$updater_running" ];then
		date
		echo "updater is stopped"
		break
	else
		date
		echo "updater is running"	
	fi
	sleep 1
done

echo "backup updater log->$folder"
mv $log_path"log_updater"* $folder

if [ $autodowngrade -eq 1 ];then
	echo "not start updater"
else
	chmod +x $updater_path$updater_exec
	$updater_path$updater_exec > /dev/null 2>&1 &
	date
	echo "updater is restarted"
fi

if [ -z "$readonly" ];then
	sudo mount -o remount,ro /
	echo "set ro"
fi

date
echo "update is done"
play_sound 31
sudo killall flash_power_led

cp ${script_path}update_out ${folder}
