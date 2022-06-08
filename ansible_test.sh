#!/bin/bash

'''
    应该直接使用剧本来完成,而不是命令的方式.
    使用ansible脚本实现: hosts文件修改
    1、[基础网络修改、恢复、检查、nscd缓存清理]
    2、[私有网络修改、恢复、检查、nscd缓存清理]
    echo "./script command"
    echo "command: {dns backupbase|dns recover|dns checkbase|dns checkvpc|base clean|vpc clean|hosts changebase|hosts changevpc|hosts recover}"
    echo "dns backupbase: 基础网络dns服务切换到备用链路"
    echo "dns backupvpc: 基础网络dns服务切换到备用链路" # 当前不支持
    # 这里使用的文件存储版本data +%s
    echo "dns recoverbase: 基础网络dns服务切换到默认链路"
    echo "dns recovervpc: vpc网络dns服务切换到默认链路"
    echo "dns checkbase: 基础网络dns配置抽查"
    echo "dns checkvpc: vpc网络dns配置抽查"
    echo "clean base: 清理基础网络设备nscd缓存"
    echo "clean vpc: 清理私有网络设备nscd缓存"
    echo "hosts changebase: 基础网络修改hosts内容解析"
    echo "hosts changevpc: vpc网络修改hosts内容解析"
    # 这里使用的文件存储版本data +%s
    echo "hosts recoverbase: 恢复hosts上一次解析内容"
    echo "hosts recovervpc: 恢复hosts上一次解析内容"
'''

# backup：基础网络切换到备用dns
function dns_backupbase {
        cd /home/dprs/rongzai/
        echo "------------基础网络: 切换dns链路到备用链路 9.237.240.8----------"
        ansible -i base_hosts_list 10.105.233.237 -m shell -a "sed -i '1 i\nameserver 9.237.240.8' /etc/resolv.conf" -u jms -b -f 50 -T 2
}

# recover：删除所有备用dns配置
function dns_recoverbase {
        cd /home/dprs/rongzai/
        echo "------------基础网络: 切换dns链路到主链路----------"
        #ansible -i base_hosts_list 10.105.233.237 -m shell -a "sed -i '0,/^nameserver 9.237.240.8$/{//d}' /etc/resolv.conf" -u jms -b -f 20 -T 2
        # 删除所有备用链路
        ansible -i base_hosts_list 10.105.233.237 -m shell -a "sed -i '/^nameserver.*9.237.240.8$/d' /etc/resolv.conf" -u jms -b -f 50 -T 2
}

# check：抽查dns配置
function dns_checkbase {
        if [ $1 == 'checkbase' ];then
          cd /home/dprs/rongzai/
          echo "------------基础网络:正在清理抽查dns配置----------"
          for i in `seq 5`
          do
            num=$((RANDOM%200+1))
            ip=`sed -n "${num}p" base_hosts_list|awk '{print $1}'`
            ansible -i base_hosts_list ${ip} -m shell -a "cat /etc/resolv.conf|grep -Ev '^$|^#'" -u jms -b -T 2 -f 5
          done
        elif [ $1 == 'checkvpc' ];then
          cd /home/dprs/rongzai/
          echo "------------vpc网络:正在清理抽查dns配置----------"
          for i in `seq 5`
          do
            num=$((RANDOM%200+1))
            ip=`sed -n "${num}p" vpc_hosts_list|awk '{print $1}'`
            ansible -i vpc_hosts_list ${ip} -m shell -a "cat /etc/resolv.conf|grep -Ev '^$|^$'" -u jms -b -T 2 -f 5
          done
        else
                echo "程序错误，请确认输入是否正确."
        fi
}

# clean：清理缓存(跑了俩次，可以优化)
function clean {
  if [ $1 == 'base' ];then
    #get base iplist
    curl -s --location -g --request GET 'http://prometheus-base.xiaoe-tools.com/api/v1/query?query=up{PrivateIpAddresses!~"10.0.*"}'|jq|grep 'PrivateIpAddresses'|awk -F'\"'  '{print $(NF-1)}' > logs/tmp_$1\_hostlist
    #change port in cvm
    iplistfile="logs/tmp_"$1"_hostlist"
    ansible -i $iplistfile all -m shell -a 'pwd' -ujms -b -f 50 -T 2 |grep 'UNREACHABLE!' > ./tmp_erriplist
    if [ $? -eq 0 ];then
      remote_port=`grep remote_port /etc/ansible/ansible.cfg|tail -1|awk '{print $NF}'`
      list=`cat tmp_erriplist|awk '{print $1}'`
      if [ $remote_port == '51800' ];then
        #修改异常ip对应端口为非标准化端口: 22
        for i in $list
          do
            sed -i "s/^$i$/$i\ ansible_ssh_port=22/" $iplistfile
          done
      else
        for i in $list
          do
            sed -i "s/^$i$/$i\ ansible_ssh_port=51800/" $iplistfile
          done
      fi
    fi
    #ansible clean
    echo "------------$1 服务:正在清理nscd缓存----------"
    ansible -i logs/tmp_$1\_hostlist all -m shell -a "nscd -i hosts" -ujms -b -f 50 -T 2
    #ansible print
    echo "------------$1 服务:查看nscd命中率----------"
    ansible -i logs/tmp_$1\_hostlist all -m shell -a "nscd -g |egrep 'hosts cache|cache hit rate'|head -4|tail -2" -ujms -b -f 50 -T 2
    #清理tmp文件
    rm -f tmp_erriplist
  elif [ $1 == 'vpc' ];then
    #get base iplist
    curl -s --location -g --request GET 'http://prometheus-base.xiaoe-tools.com/api/v1/query?query=up{PrivateIpAddresses=~"10.0.*",InstanceName!~".*数据分析.*|.*emr.*"}'|jq|grep 'PrivateIpAddresses'|awk -F'\"'  '{print $(NF-1)}' > logs/tmp_$1\_hostlist
    #change port in cvm
    iplistfile="logs/tmp_"$1"_hostlist"
    ansible -i $iplistfile all -m shell -a 'pwd' -ujms -b -f 50 -T 2 |grep 'UNREACHABLE!' > ./tmp_erriplist
    if [ $? -eq 0 ];then
      remote_port=`grep remote_port /etc/ansible/ansible.cfg|tail -1|awk '{print $NF}'`
      list=`cat tmp_erriplist|awk '{print $1}'`
      if [ $remote_port == '51800' ];then
        #修改异常ip对应端口为非标准化端口: 22
        for i in $list
          do
            sed -i "s/^$i$/$i\ ansible_ssh_port=22/" $iplistfile
          done
      else
        for i in $list
          do
            sed -i "s/^$i$/$i\ ansible_ssh_port=51800/" $iplistfile
          done
      fi
    fi
    #ansible clean
    echo "------------$1 服务:正在清理nscd缓存----------"
    ansible -i logs/tmp_$1\_hostlist all -m shell -a "nscd -i hosts" -ujms -b -f 50 -T 2
    #ansible print
    echo "------------$1 服务:查看nscd命中率----------"
    ansible -i logs/tmp_$1\_hostlist all -m shell -a "nscd -g |egrep 'hosts cache|cache hit rate'|head -4|tail -2" -ujms -b -f 50 -T 2
    #清理tmp文件
    rm -f tmp_erriplist
  else
    echo "程序错误，请确认输入是否正确."
  fi
}

'''
    echo "hosts changebase: 基础网络修改hosts内容解析"
    echo "hosts changevpc: vpc网络修改hosts内容解析"
    # 这里使用的文件存储版本data +%s
    echo "hosts recoverbase: 恢复hosts上一次解析内容"
    echo "hosts recovervpc: 恢复hosts上一次解析内容"
'''
#  这里得使用剧本来实现了
function hosts_change {
        cd /home/dprs/rongzai/
        if [ $1 == 'change' ];then
          echo "------------基础网络下，备份hosts文件----------"
          time=`date +%s`
          logfile='/tmp/hosts-changelist.log'
          cp -a /etc/hosts /etc/hosts-{$time}
          echo $time >> $logfile
          echo "------------基础网络下，替换hosts文件----------"
          sleep 1
          ansible -i base_hosts_list all -m copy -a 'src=./resolution_base.list dest=/etc/hosts' -ujms -b -f 50 -T 2
          echo "------------清理nscd缓存----------------------"
          ansible -i base_hosts_list all -m shell -a 'nscd -i hosts' -u jms -b -f 50 -T 2
        elif [ $1 == 'recover' ];then
          echo "------------基础网络下，恢复hosts文件----------"
          ansible -i base_hosts_list all -m shell -a 'cp -f /etc/hosts_bak-2022-03-16 /etc/hosts' -ujms -b -f 50 -T 2
          echo "------------清理nscd缓���----------------------"
          ansible -i base_hosts_list all -m shell -a 'nscd -i hosts' -u jms -b -f 50 -T 2
        else
          echo "it is  nothing to done..."
        fi
}

function vpc_hosts {
        cd /home/dprs/rongzai/
        if [ $1 == 'change' ];then
          echo "------------vpc网络下，替换hosts文件----------"
          sleep 1
          ansible -i vpc_hosts_list all -m copy -a 'src=./resolution_vpc.list dest=/etc/hosts' -ujms -b -f 20 -T 2
          echo "------------清理nscd缓存----------------------"
          ansible -i vpc_hosts_list all -m shell -a 'nscd -i hosts' -u jms -b -f 20 -T 2
        elif [ $1 == 'recover' ];then
          echo "------------vpc网络下，恢复hosts文件----------"
          sleep 1
          ansible -i vpc_hosts_list all -m shell -a 'cp -f /etc/hosts_bak-2022-03-16 /etc/hosts' -ujms -b -f 20 -T 2
          echo "------------清理nscd缓存----------------------"
          ansible -i vpc_hosts_list all -m shell -a 'nscd -i hosts' -u jms -b -f 20 -T 2
        else
          echo "it is  nothing to done..."
        fi
}

case $1 in
backup)
    dns_running
    ;;
recover)
    dns_recover
    ;;
check)
    dns_check $2
    ;;
clean)
    clean $2
    ;;
base)
    base_hosts $2
    ;;
vpc)
    vpc_hosts $2
    ;;
-h|--help)
    echo "./script command"
    echo "command: {backup|recover|check base|check vpc|clean servicename|base change|base recover|vpc change|vpc recover}"
    echo
    echo "-h --help 帮助"
    echo "backup: 基础网络dns服务切换到备用链路"
    echo "recover: vpc网络dns服务切换到默认链路"
    echo "check base: 基础网络dns配置抽查"
    echo "check vpc: vpc网络dns配置抽查"
    echo "clean servicename: 清理对应service的nscd缓存"
    echo "base change: 基础网络修改hosts内容解析"
    echo "base recover: 基础网络恢复hosts内容解析"
    echo "vpc change: vpc网络修改hosts内容解析"
    echo "vpc recover: vpc网络恢复hosts内容解析"
    ;;
*)
    echo $"Usage: $0 {backup|recover|check base|check vpc|clean servicename|base change|base recover|vpc change|vpc recover}"
    exit 2
esac