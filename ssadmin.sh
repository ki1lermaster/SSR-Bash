#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
# Copyright (c) 2014 hellofwy
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do 
      DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
      SOURCE="$(readlink "$SOURCE")"
      [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" 
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

. $DIR/sslib.sh

usage () {
    cat $DIR/sshelp
}
wrong_para_prompt() {
    echo "参数输入错误!"
}

#根据用户文件生成ssserver配置文件
create_json () {
    echo '{' > $JSON_FILE.tmp
    sed -E 's/(.*)/    \1/' $DIR/ssmlt.template >> $JSON_FILE.tmp 
    awk '
    BEGIN {
        i=1;
        printf("    \"port_password\": {\n");
    }
    ! /^#|^\s*$/ {
        port=$1;
        pw=$2;
        ports[i++] = port;
        pass[port]=pw;
    }
    END {
        for(j=1;j<i;j++) {
            port=ports[j];
            printf("        \"%s\": \"%s\"", port, pass[port]);
            if(j<i-1) printf(",");
            printf("\n");
        }
        printf("    }\n");
    }
    ' $USER_FILE >> $JSON_FILE.tmp
    echo '}' >> $JSON_FILE.tmp
    mv $JSON_FILE.tmp $JSON_FILE
    rm -rf /usr/local/shadowsocks/config.json
    cp $JSON_FILE /usr/local/shadowsocks/config.json
}

run_ssserver () {
    python /usr/local/shadowsocks/shadowsocks/server.py -d start
}

check_ssserver () {
    SSPID=$(ps -ef|grep 'python /usr/local/shadowsocks/shadowsocks/server.py -d start' |grep -v grep |awk '{print $2}')
    if [[ $SSPID != "" ]]; then
        return 1
    else
        return 0
    fi
}

check_sscounter () {
    if [ -e $SSCOUNTER_PID ]; then
        ps $(cat $SSCOUNTER_PID) 2>/dev/null | grep sscounter 2>/dev/null
        return $?
    else
        return 1
    fi
}

start_ss () {
    if [ ! -e $USER_FILE ]; then
        echo "还没有用户，请先添加一个用户"
        return 1
    fi
    check_ssserver
    if [[ $? == 1 ]]; then
            echo 'SSR服务已启动，同一实例不能启动多次！'
            return 1
    fi
    create_json

    if [ -e $SSCOUNTER_PID ]; then
        if check_sscounter ; then 
            kill `cat $SSCOUNTER_PID`
        else
            rm $SSCOUNTER_PID
        fi
    fi

    echo 'sscounter启动中...'
    ( $DIR/sscounter.sh ) & 
    echo $! > $SSCOUNTER_PID
    if check_sscounter; then 
        echo 'sscounter已启动'
    else
        echo 'sscounter启动失败'
        return 1
    fi

    echo 'SSR启动中...'
    run_ssserver 
    sleep 1
    check_ssserver
    if [[ $? == 1 ]]; then
        echo 'SSR已启动'
    else
        echo 'SSR启动失败'
        return 1
    fi
}

stop_ss () {
    check_ssserver
    if [[ $? == 1 ]]; then
        kill $SSPID
        del_ipt_chains 2> /dev/null
        echo 'SSR已关闭'
    else
        echo 'SSR未启动'
    fi
    if check_sscounter; then 
        kill `cat $SSCOUNTER_PID`
        rm $SSCOUNTER_PID
        echo 'sscounter已关闭'
    else
        echo 'sscounter未启动'
    fi
}

restart_ss () {
    stop_ss
    start_ss
}
    

status_ss () {
    check_ssserver
    if [[ $? == 1 ]]; then
        echo 'SSR正在运行'
    else
        echo 'SSR未启动'
    fi
    if check_sscounter; then 
        echo 'sscounter正在运行'
    else
        echo 'sscounter未启动'
    fi
}

bytes2gb () {
    TLIMIT=$1
    echo "$TLIMIT" |
    sed -E 's/[kK][bB]?/ * 1024/' |
    sed -E 's/[mM][bB]?/ * 1024 * 1024/' |
    sed -E 's/[gG][bB]?/ * 1024 * 1024 * 1024/' |
    sed -E 's/[tT][bB]?/ * 1024 * 1024 * 1024 * 1024/' |
    bc |
    awk '{printf("%.0f", $1)}'
}
check_port_range () {
    PORT=$1
    if (( ($PORT > 0) && ($PORT <= 65535 ) && ($PORT != 137) && ($PORT !=138) && ($PORT != 53) && ($PORT != 80) )); then
        return 0
    else
        return 1
    fi
}
add_user () {
    if [ "$#" -ne 3 ]; then
        wrong_para_prompt;
        return 1
    fi
    PORT=$1
    if check_port_range $PORT; then
        :
    else
        wrong_para_prompt;
        return 1
    fi
    PWORD=$2
    TLIMIT=$3
    TLIMIT=`bytes2gb $TLIMIT`
    if [ ! -e $USER_FILE ]; then
        echo "\
# 以空格、制表符分隔
# 端口 密码 流量限制
# 2345 abcde 1000000" > $USER_FILE;
    fi
    cat $USER_FILE |
    awk '
    {
        if($1=='$PORT') exit 1
    }'
    if [ $? -eq 0 ]; then
        echo "\
$PORT $PWORD $TLIMIT" >> $USER_FILE;
    else
        echo "用户已存在!"
        return 1
    fi
# 重新生成配置文件，并加载
        create_json
        add_rules $PORT
        stop_ss
	    start_ss
# 更新流量记录文件
    update_or_create_traffic_file_from_users
    calc_remaining
}
add_user_more () {
until [[ $num -lt 0 ]];do
	if [ "$#" -ne 3 ]; then
			wrong_para_prompt;
			return 1
		fi
		PORT=$pport
		if check_port_range $PORT; then
			:
		else
			wrong_para_prompt;
			return 1
		fi
		PWORD=$pw
		TLIMIT=$ll
		TLIMIT=`bytes2gb $TLIMIT`
		if [ ! -e $USER_FILE ]; then
        echo "\
	# 以空格、制表符分隔
	# 端口 密码 流量限制
	# 2345 abcde 1000000" > $USER_FILE;
		fi
		cat $USER_FILE |
		awk '
		{
			if($1=='$PORT') exit 1
		}'
		if [ $? -eq 0 ]; then
			echo "\
	$PORT $PWORD $TLIMIT" >> $USER_FILE;
		else
			echo "用户已存在!"
			return 1
		fi
	# 重新生成配置文件，并加载
			create_json
			add_rules $PORT
	# 更新流量记录文件
		update_or_create_traffic_file_from_users
		calc_remaining
	((num—));
	((pport—));
	done; 
	stop_ss
	start_ss
}
del_user () {
	if [ ! -e $USER_FILE ]; then
        echo "还没有用户，请先添加一个用户"
        return 1
    fi

    if [ "$#" -ne 1 ]; then
        wrong_para_prompt;
        return 1
    fi
    PORT=$1
    if check_port_range $PORT; then
        :
    else
        wrong_para_prompt;
        return 1
    fi
    if [ -e $USER_FILE ]; then
        sed -i '/^\s*'$PORT'\s/ d' $USER_FILE
    fi
# 重新生成配置文件，并加载
        check_ssserver
        if [[ $? == 1 ]];then
            kill $SSPID
        fi
        create_json
        del_rules $PORT 2>/dev/null
        del_reject_rules $PORT 2>/dev/null
        run_ssserver
        clear
# 更新流量记录文件
    update_or_create_traffic_file_from_users
    calc_remaining
}

change_user () {
    if [ "$#" -ne 3 ]; then
        wrong_para_prompt;
        return 1
    fi
    PORT=$1
    if check_port_range $PORT; then
        :
    else
        wrong_para_prompt;
        return 1
    fi
    PWORD=$2
    TLIMIT=$3
    TLIMIT=`bytes2gb $TLIMIT`
    if [ ! -e $USER_FILE ]; then
        echo "目前还无用户，请先添加用户" 
        return 1
    fi
    if grep -q "^\s*$PORT\s" $USER_FILE; then
        cat $USER_FILE |
        awk '
        {
            if($1=='$PORT') {
                printf("'$PORT' '$PWORD' '$TLIMIT'\n");
            } else {
                print $0
            }
        }' > $USER_FILE.tmp;
        mv $USER_FILE.tmp $USER_FILE
        # 重新生成配置文件，并加载
            check_ssserver
            if [[ $? == 1 ]];then
            kill $SSPID
            fi
            create_json
            add_rules $PORT
            run_ssserver
        # 更新流量记录文件
        update_or_create_traffic_file_from_users
        calc_remaining
    else
        echo "此用户不存在!"
        return 1
    fi
}

change_passwd () {
    if [ "$#" -ne 2 ]; then
        wrong_para_prompt;
        return 1
    fi
    PORT=$1
    if check_port_range $PORT; then
        :
    else
        wrong_para_prompt;
        return 1
    fi
    PWORD=$2
    if [ ! -e $USER_FILE ]; then
        echo "目前还无用户，请先添加用户" 
        return 1
    fi
    if grep -q "^\s*$PORT\s" $USER_FILE; then
        cat $USER_FILE |
        awk '
        {
            if($1=='$PORT') {
                printf("'$PORT' '$PWORD' %s\n", $3);
            } else {
                print $0
            }
        }' > $USER_FILE.tmp;
        mv $USER_FILE.tmp $USER_FILE
        # 重新生成配置文件，并加载
            check_ssserver
            if [[ $? == 1 ]];then
            kill $SSPID
            fi
            create_json
            add_rules $PORT
            run_ssserver
        # 更新流量记录文件
        update_or_create_traffic_file_from_users
        calc_remaining
    else
        echo "此用户不存在!"
        return 1
    fi
}

change_limit () {
    if [ "$#" -ne 2 ]; then
        wrong_para_prompt;
        return 1
    fi
    PORT=$1
    if check_port_range $PORT; then
        :
    else
        wrong_para_prompt;
        return 1
    fi
    TLIMIT=$2
    TLIMIT=`bytes2gb $TLIMIT`
    if [ ! -e $USER_FILE ]; then
        echo "目前还无用户，请先添加用户"
        return 1
    fi
    if grep -q "^\s*$PORT\s" $USER_FILE; then
        cat $USER_FILE |
        awk '
        {
            if($1=='$PORT') {
                printf("'$PORT' %s '$TLIMIT'\n", $2);
            } else {
                print $0
            }
        }' > $USER_FILE.tmp;
        mv $USER_FILE.tmp $USER_FILE
        # 更新流量记录文件
        update_or_create_traffic_file_from_users
        calc_remaining
    else
        echo "此用户不存在!"
        return 1
    fi
}

change_all_limit () {
    if [ "$#" -ne 1 ]; then
        wrong_para_prompt;
        return 1
    fi
    TLIMIT=$1
    TLIMIT=`bytes2gb $TLIMIT`
    if [ ! -e $USER_FILE ]; then
        echo "目前还无用户，请先添加用户"
        return 1
    fi
    cat $USER_FILE |
    awk '
    {
        if($0 !~ /^#/ && $0 !~ /^\s.*$/) {
            printf("%s %s '$TLIMIT'\n", $1, $2);
        } else {
            print $0
        }
    }' > $USER_FILE.tmp;
    mv $USER_FILE.tmp $USER_FILE
    # 更新流量记录文件
    update_or_create_traffic_file_from_users
    calc_remaining
}

show_user () {
    if [ $# -eq 0 ]; then
        cat $TRAFFIC_FILE;
    else
        if [ "$#" -ne 1 ]; then
            wrong_para_prompt;
            return 1
        fi
        PORT=$1
        if check_port_range $PORT; then
            :
        else
            wrong_para_prompt;
            return 1
        fi
        res=`grep "^\s*$PORT\s" $TRAFFIC_FILE`
        if [ -z "$res" ]; then
            echo "此用户不存在!"
        else 
            head -n1 $TRAFFIC_FILE
            echo  "$res"
        fi
    fi
}

show_passwd () {
    if [ $# -eq 0 ]; then
        cat $USER_FILE;
    else
        if [ "$#" -ne 1 ]; then
            wrong_para_prompt;
            return 1
        fi
        PORT=$1
        if check_port_range $PORT; then
            :
        else
            wrong_para_prompt;
            return 1
        fi
        res=`grep "^\s*$PORT\s" $USER_FILE`
        if [ -z "$res" ]; then
            echo "此用户不存在!"
        else 
            head -n2 $USER_FILE
            echo  "$res"
        fi
    fi
}
reset_limit () {
    if [ ! -e $USER_FILE ]; then
        echo "目前还无用户，请先添加用户"
        return 1
    fi
    if [ $# -eq 0 ]; then
        cat $USER_FILE |
        awk '
        {
            if($0 !~ /^#/ && $0 !~ /^\s.*$/) {
                printf("%s %s 0\n", $1, $2);
            } else {
                print $0
            }
        }' > $USER_FILE.tmp;
        mv $USER_FILE.tmp $USER_FILE
        # 更新流量记录文件
        update_or_create_traffic_file_from_users
        calc_remaining
    else
        if [ "$#" -ne 1 ]; then
            wrong_para_prompt;
            return 1
        fi
        PORT=$1
        if check_port_range $PORT; then
            :
        else
            wrong_para_prompt;
            return 1
        fi
        if grep -q "^\s*$PORT\s" $USER_FILE; then
            cat $USER_FILE |
            awk '
            {
                if($1=='$PORT') {
                    printf("'$PORT' %s 0\n", $2);
                } else {
                    print $0
                }
            }' > $USER_FILE.tmp;
            mv $USER_FILE.tmp $USER_FILE
            # 更新流量记录文件
            update_or_create_traffic_file_from_users
            calc_remaining
        else
            echo "此用户不存在!"
            return 1
        fi
    fi
}

reset_used () {
    if [ ! -e $USER_FILE ]; then
        echo "目前还无用户，请先添加用户"
        return 1
    fi
    while [ -e $TRAFFIC_LOG.lock ]; do
        sleep 1
    done
    touch $TRAFFIC_LOG.lock
    if [ $# -eq 0 ]; then
        cat $TRAFFIC_LOG |
        awk '
        {
            if($0 !~ /^#/ && $0 !~ /^\s.*$/) {
                printf("%-5d\t0\n", $1);
            } else {
                print $0
            }
        }' > $TRAFFIC_LOG.tmp;
        mv $TRAFFIC_LOG.tmp $TRAFFIC_LOG
    else
        if [ "$#" -ne 1 ]; then
            wrong_para_prompt;
            return 1
        fi
        PORT=$1
        if check_port_range $PORT; then
            :
        else
            wrong_para_prompt;
            return 1
        fi
        if grep -q "^\s*$PORT\s" $USER_FILE; then
            cat $TRAFFIC_LOG |
            awk '
            {
                if($1=='$PORT') {
                    printf("%-5d\t0\n", '$PORT');
                } else {
                    print $0
                }
            }' > $TRAFFIC_LOG.tmp;
            mv $TRAFFIC_LOG.tmp $TRAFFIC_LOG
        else
            echo "此用户不存在!"
            rm $TRAFFIC_LOG.lock
            return 1
        fi
    fi
    rm $TRAFFIC_LOG.lock
    # 更新流量记录文件
    calc_remaining
}

if [ "$#" -eq 0 ]; then
    usage
    exit 0
fi
case $1 in
    -h|h|help )
        usage
        exit 0;
        ;;
    -v|v|version )
        echo 'ssr-bash Version 1.0-beta1, 2016-12-6, Copyright (c) 2014-2016 hellofwy Modified by FunctionClub'
        exit 0;
        ;;
esac
if [ "$EUID" -ne 0 ]; then
    echo "必需以root身份运行"
    exit 1;
fi
case $1 in
    add )
        shift
        add_user $1 $2 $3
        ;;
	addmore )
		shift
		add_user_more $start $pw $ll $num 
		;;
    del )
        shift
        del_user $1
        ;;
    show )
        shift
        show_user $1
        ;;
    showpw )
        shift
        show_passwd $1
        ;;
    change )
        shift
        change_user $1 $2 $3
        ;;
    cpw )
        shift
        change_passwd $1 $2
        ;;
    clim )
        shift
        change_limit $1 $2
        ;;
    rlim )
        shift
        if [ $# -eq 0 ]; then
            echo "请指定用户端口号"
            exit 1
        else
            reset_limit $1
        fi
        ;;
    change_all_limit )
        shift
        change_all_limit $1
        ;;
    reset_all_limit )
        shift
        reset_limit
        ;;
    rused )
        shift
        if [ $# -eq 0 ]; then
            echo "请指定用户端口号"
            exit 1
        else
            reset_used $1
        fi
        ;;
    reset_all_used )
        shift
        reset_used
        ;;
    start )
        start_ss 
        ;;
    stop )
        stop_ss 
        ;;
    restart )
        restart_ss 
        ;;
    status )
        status_ss
        ;;
    soft_restart )
        soft_restart_ss 
        ;;
    lrules )
        list_rules
        ;;
    * )
        usage
        ;;
esac

