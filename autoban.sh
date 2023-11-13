#!/bin/bash

# 定义新的nftables表、链和集合
table_name="custom_block"
chain_name="input"
set_name="blocked_ips"

# 使用journalctl和grep获取日志
log_output=$(journalctl -k | grep nftables-reject)

# 使用正则表达式匹配IP地址
regex="SRC=([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\.[0-9]{1,3}"

# 创建新的nftables表、链和集合
nft add table ip $table_name
nft add chain ip $table_name $chain_name { type filter hook input priority -1 \; }
nft add set ip $table_name $set_name { type ipv4_addr\; flags interval\; }

# 在新的nftables链中添加规则来屏蔽集合中的IP地址
if ! nft list chain ip $table_name $chain_name | grep -q "ip saddr @blocked_ips counter packets"
then
    # 如果规则不存在，添加规则
    nft add rule ip $table_name $chain_name ip saddr @blocked_ips counter drop
fi
# 遍历日志输出
while IFS= read -r line
do
    if [[ $line =~ $regex ]]
    then
        # 获取匹配到的IP地址的前三个部分
        ip_prefix=${BASH_REMATCH[1]}
        
        # 构造CIDR
        cidr="$ip_prefix.0/24"
        
        # 检查IP地址是否已经在集合中
        if ! nft list set ip $table_name $set_name | grep -q $cidr
        then
            # 如果IP地址不在集合中，将其添加到集合中
            nft add element ip $table_name $set_name { $cidr }
            echo "adding element $table_name $set_name $cidr "
        fi
    fi
done <<< "$log_output"

nft list table $table_name > /etc/nftables.conf
