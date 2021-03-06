#!/bin/sh
#########################################################################################################
#function:                                             																									#
#This script is used for log cleanup. Create a compressed package for the previous day's logs,      		#
#archive them timely, check storage, and delete the earliest archive files when storage is insufficient.#
#version:1.0.0.0    author:wangxinru                                																		#
#version:2.0.0.0    author:shanliang    rewrite the script                 															#
#version:2.0.0.1    author:shanliang    bugfix:Monday&Sunday do not calculate exact    									#
#version:3.0.0.0    author:shanliang    algorithm changed:file=>tar.bz2 modified file=>bz2=>tar 				#
#version:3.0.0.1    author:shanliang    bugfix                        																  #
#version:3.0.0.2    author:shanliang    bugfix:change partitionAvail calls          										#
#version:4.0.0.0		author:shanliang		new function! log archive with multiple path										#
#version:4.1.0.0		author:shanliang		adding searching function																				#
#version:4.1.0.1		author:shanliang		bugfix:partitionAvail getting failed														#
#version:4.2.0.1		author:shanliang		performance optimization: search in memory											#
#version:4.2.0.2		author:shanliang		set the execution priority of scripts(nicevalue)								#
#version:4.2.0.3		author:shanliang		deleted the unused method																				#
#########################################################################################################
#variable parameters
#Log file path
#logs=("/root/scripts/logs":"tomcat.log4j.*" "/root/scripts/logs_1":"tomcat.log5j.*")
logs=("/root/scripts/logs":"tomcat.log4j.*" "/root/scripts/logs2":"tomcat.log4j.*" "/root/scripts/logs3":"tomcat.log4j.*" "/root/scripts/logs2/logs22":"tomcat.log4j.*")
logExpiredDays="30"
#tar archive file locate 
logTarPath="/archive/"
#tar archive file prefix 
logTarPrefix="history_Archiving_"
#disk available threshold (MB)
Diskthreshold="10100"
#temp file locate
tempDir="/tmp/logarchive"
#compress type:bzip2:gzip:none
compress="bzip2"
#nice value
nicevalue=19
#scripts parameters DO NOT EDIT
initParameters(){
		setNiceLow
    today=`date "+%Y-%m-%d %H:%M:%S"`
    setPartitionAvail		
    mkdir -p $logTarPath  
}
setNiceLow(){
				logging  "INFO" "$(renice -n $nicevalue -p $$)"
}
setPartitionAvail(){
     partitionAvail=`df -hP --block-size=1m $logTarPath 2>/dev/null| sed -n '2,$p' |gawk 'BEGIN{FS=" "}{print $4}'`
}
getMondayDate(){
    if [[ $((`date -d "$1" "+%w"`)) = 0 ]];then
        itv=6
    else
        itv=$((`date -d "$1" "+%w"`-1))
    fi
    echo $(date -d "$1 $itv days ago" "+%Y%m%d")
}
getSundayDate(){
    if [[ $((`date -d "$1" "+%w"`)) = 0 ]];then
        itv=0
    else
        itv=$((7-`date -d "$1" "+%w"`))
    fi
    echo $(date -d "$1 $itv days" "+%Y%m%d")
}
getFileModifyDate(){
    echo `ls --full-time $1 |gawk '{print $6}'`
}
logging(){
    if [[ "$1" = "MARK" ]];then
        echo -e "$2"
    elif [[ "$1" = "INFO" ]];then
        echo -e [`date "+%Y-%m-%d %H:%M:%S"`]"\033[38;32m $2 \033[0m"
    elif [[ "$1" = "ERROR" ]];then
        echo -e [`date "+%Y-%m-%d %H:%M:%S"`]"\033[36;41m $2 \033[0m"
    fi
}
archiving_all_his(){
		logPath=$1
		logFormat=$2
    for file in `find $logPath -maxdepth 1 -mindepth 1 -iname "$logFormat" -type f`
    do
        if [[ -f $file ]];then
            fileMdate=`getFileModifyDate $file`
            fileMdate_Monday=`getMondayDate $fileMdate`
            fileMdate_Sunday=`getSundayDate $fileMdate`
            filepath="$logTarPath""$logTarPrefix""$fileMdate_Monday""-""$fileMdate_Sunday"".tar"
            comp=""
            comp_postfix=""
            case $compress in 
            "bzip2") comp="bzip2 -z $file"
                 comp_postfix=".bz2"
                ;;
            "gzip") comp="gzip $file"
                 comp_postfix=".gz"
                ;;
            *) logging "INFO" "NO COMPRESS config ...";;
            esac
            logging "INFO" "adding $file$comp_postfix into $filepath"
            if [[ ! -f $filepath ]];then
                #2.0 method
                #tar -cpPjf $filepath $file &>/dev/null
                #3.0 method
                if [[ "$comp_postfix" != "" ]];then
                    if `eval $comp`;then
                        logging "INFO" "compress the file $file with $compress success ..."
                        tar -cPpf $filepath $file$comp_postfix &>/dev/null
                    else
                        logging "ERROR" "compress the file $file with $compress failed ..."
                        continue
                    fi
                else
                    tar -cPpf $filepath $file &>/dev/null
                fi
            else
                if [[ "$comp" != "" ]];then
                    if `eval $comp`;then
                        logging "INFO" "compress the file $file with $compress success ..."
                        tar -rPpf $filepath $file$comp_postfix &>/dev/null
                    else
                        logging "ERROR" "compress the file $file with $compress failed ..."
                        continue
                    fi
                else
                    tar -rPpf $filepath $file &>/dev/null
                fi
                
            fi
            if ! `tar -tf $filepath  $file$comp_postfix &>/dev/null` ;then
                logging "ERROR" "adding $file$comp_postfix failed ..."
                sleep 2
            else
                logging "INFO" "adding $file$comp_postfix success ..."
                logging "INFO" "removing $file$comp_postfix..."
                if `/bin/rm -f $file$comp_postfix >&/dev/null` ; then
                    logging "INFO" "removing the file $file$comp_postfix success ..."
                else
                    logging "ERROR" "removing the file $file$comp_postfix failed ..."
                fi
            fi
            unset fileMdate fileMdate_Monday fileMdate_Sunday filepath
        else
            logging "ERROR" "[ $file ] Not Found ..."
        fi
        
    done
    unset file
}
archiving(){
    logging "MARK" "########################################################################"
    logging "INFO" "Now starting to archive ..."
    archiving_all_his $1 $2
    logging "INFO" "archiving has been finished ..."
    logging "MARK" "########################################################################"
}
fileIsExpire(){
    prefixLength=$((`echo $logTarPrefix | wc -c`+8+1))
    fileArchivedLastDate=`echo $1 | cut -c $prefixLength-$(($prefixLength+7))`
    if [[ $((($(date -d "$today" +%s) - $(date -d "$fileArchivedLastDate" +%s))/(24*60*60))) -gt $logExpiredDays ]] ;then
        return 0
    else
        return 1
    fi
    
}
removeTheExpires(){
    logging "MARK" "########################################################################"
    logging "INFO" "searching the expire tarball ..."
    for file in `ls -1 -F $logTarPath | grep -v [/$] | grep "$logTarPrefix" `
    do
        if `fileIsExpire $file` ; then
            logging "INFO" "removing the expire file : $file ..."
            if `/bin/rm -f "$logTarPath$file" &>/dev/null` ;then
                logging "INFO" "removing the expire file $file success ..."
            else
                logging "ERROR" "removing the expire file $file failed ..."
            fi
        fi
    done
    logging "INFO" "the searching has been finished ..."
    logging "MARK" "########################################################################"

}
diskIsFull(){
    if [[ $partitionAvail -lt $Diskthreshold ]];then 
        return 0
    else
        return 1
    fi  
}
getOldest_tarball(){
    tmpDate="99999999"
    for file in `ls -1 -F $logTarPath | grep -v [/$] | grep "$logTarPrefix" `
    do
        prefixLength=$((`echo $logTarPrefix | wc -c`+8+1))
        fileArchivedLastDate=`echo $1 | cut -c $prefixLength-$(($prefixLength+7))`
        if [[ $fileArchivedLastDate < $tmpDate ]];then
            oldest_tarball="$file"
            tmpDate=$fileArchivedLastDate
        fi
    done
}
removeTheFileWhenDiskIsFull(){
    logging "MARK" "########################################################################"
    logging "INFO" "starting disk space check ..."
    while true
    do
        setPartitionAvail
        if ! `diskIsFull` ;then
            logging "INFO" "the disk space is fine [ Available : $partitionAvail MB] ... "
            break
        else 
            logging "INFO" "the disk space is insufficient [ Available : $partitionAvail MB] ..."
            getOldest_tarball
            if [[ ! -f $logTarPath$oldest_tarball ]];then
                logging "ERROR" "No File Can be removed ..."
                break   
            fi
            logging "INFO" "Now remove the oldest tarball : $logTarPath$oldest_tarball ..."
            if `/bin/rm -f $logTarPath$oldest_tarball &>/dev/null` ;then
                logging "INFO" "the file $logTarPath$oldest_tarball  has been removed ..."
            else
                logging "ERROR" "the file $logTarPath$oldest_tarball  cannot be  removed ..."
            fi
        fi
    done
    logging "INFO" "disk check has been finished ..."
    logging "MARK" "########################################################################"
}
main(){
    initParameters
		count=${#logs[@]}
		if [ $count -gt 0 ]; then
			for((i=0;i<$count;i++))
			do
				logPath=`echo "${logs[i]}"|cut -d ':' -f1`
				logFormat=`echo "${logs[i]}"|cut -d ':' -f2`
				archiving $logPath $logFormat
			done
		fi
    removeTheExpires
    removeTheFileWhenDiskIsFull
}
search(){
		for f in `find $logTarPath`
		do
			
			if `file $f | grep "tar archive" &>/dev/null`;then
				for z in `tar -tf $f 2>/dev/null`
					do
						 if `echo "$z" |grep -P '.bz2$' &>/dev/null`;then
						 		comp="tar -xf "$f" "$z" -O 2>/dev/null | bzcat "
						 elif `echo "$z"  |grep -P '.gz$' &>/dev/null`;then
						 		comp="tar -xf "$f" "$z" -O 2>/dev/null | gzip -d "
						 fi
						 comp="$comp | grep -n "$1" | gawk -F ":" '{print \$1}'"
						 for g in `eval $comp`
						 do
								 echo "$f >> $z >> line [$g] >> found the key value [$1]"
						 done
					done
			fi
		done
}
case $# in
0)  main ;;
1)  search $1;;
*)  
    echo "what ??"
;; 
esac