#!/bin/bash
check_file_func()
{
	dpkg -s asiair |grep Version
	if [ $? -ne 0 ];then
		echo error\(not install\)
		return 1
	fi
	
	IFS=$'\n'

	for f in $(dpkg -L asiair); do 
		
		#skip directory 
		if [ -d "$f" ];then
#		echo skip dir:$f
			continue
		fi
#	echo file=$f

		#软连接：本身或目标文件不存在都能检测到
		if [ ! -f "$f" ];then
			echo error\(not exist\):$f
			return 1
		fi
		
		file_out=$(file "$f")
#	echo $file_out
		echo $file_out|grep 'LSB executable' > /dev/null 2>&1 
		if [ $? -eq 0 ];then
			ldd "$f"|grep 'not found' #> /dev/null 2>&1
			if [ $? -eq 0 ];then
				echo error\(dependency\):$f
				return 1
			fi
		fi
	done

	return 0
}

check_file_func

#echo ret=$?;exit 0

if [ $? -ne 0 ];then
	date
	echo "updating"
	/etc/zwo/run_old_update.sh --autodowngrade
else
	echo not need update
fi

