---
title: Docker—网络模式
tags:
  - docker
  - network
categories:
  - docker
toc: true
date: 2018-03-28 17:14:17
updated: 2018-03-28 17:14:17
---

### 前言
最近对docker的网络很感兴趣，记录一下学习过程。当Docker进程启动时，会在主机上创建一个名为docker0的虚拟网卡，也可以说是虚拟网桥，这只是docker网络模式的一种。实际上，Docker有四种网络模式，我们来逐个讲解。

<!--more-->

环境：

- CentOS Linux release 7.1.1503 (Core)    docker-17.05.0-ce

| card    | ip           | mac               |
| :------ | :----------- | :---------------- |
| docker0 | 172.17.43.1  | 02:42:8b:af:34:a9 |
| ens33   | 192.168.1.50 | 00:50:56:3a:64:16 |
- Ubuntu 14.04.5 LTS  docker-18.03.0-ce

| card    | ip           | mac                 |
| ------- | ------------ | ------------------- |
| docker0 | 172.17.42.1  | 02:42: ab :f3:f3:95 |
| eth0    | 192.168.1.48 | 00:0c:29:3d:8f:81   |


### Bridge模式
前面已经提到，docker会在主机上创建docker0的虚拟网桥，这台主机上的Docker容器都会连接到这个虚拟网桥docker0上。docker0和物理交换机类似，将主机上所有容器通过交换机构成了一个二层网络。docker0在二层网络中扮演默认网关的角色，给子网中容器分配ip，且容器的默认网关就是docker0的IP地址

这里我启动了一个容器，id为1e5c62d8e949，命令如下：

```
docker run -ti centos /bin/bash 等效于 docker run -ti --net=bridge centos /bin/bash
```

其ip和gateway如图：

![](Docker—网络模式\docker-ip-gateway.png)

docker在主机上创建一对虚拟网卡veth pair设备，将veth pair设备的一端放在创建的容器中，并命名为eth0（容器的网卡），另一端放在主机中，以vethxxx这样类似的名字命名，并将这个网络设备加入到docker0网桥中。brctl show和ethtool命令查看：

![](Docker—网络模式\docker-host.png)

![](Docker—网络模式\docker-container.png)

bridge模式是docker的默认网络模式，不写--net参数，就是bridge模式。使用docker run -p时，docker实际是在iptables做了DNAT规则，实现端口转发功能。可以使用iptables -t nat -vnL查看。

bridge模式如下图所示：
![](Docker—网络模式\bridge.png)
### Host模式

在这个模式下，容器将不会获得一个独立的Network Namespace，而是和宿主机共用一个Network Namespace。容器将不会虚拟出自己的网卡，配置自己的IP等，而是使用宿主机的IP和端口。但是，容器的其他方面，如文件系统、进程列表等还是和宿主机隔离的。

创建host模式容器命令如下：

```
docker run -it --net=host centos /bin/bash
```

宿主机ifconfig查看配置信息：

![](Docker—网络模式\host-ifconfig.png)

host模式容器配置信息：

![](Docker—网络模式\container-ifconfig.png)

host模式结构：

![](Docker—网络模式\host.png)

### Container模式

这个模式指定新创建的容器和已经存在的一个容器共享一个 Network Namespace，而不是和宿主机共享。新创建的容器不会创建自己的网卡，配置自己的 IP，而是和一个指定的容器共享 IP、端口范围等。同样，两个容器除了网络方面，其他的如文件系统、进程列表等还是隔离的。两个容器的进程可以通过 lo 网卡设备通信。

创建container模式容器命令如下：

```
# 1e5c62d8e949为之前创建的bridge模式的容器id
docker run -it --net=container:1e5c62d8e949 centos /bin/bash
```

查看两个容器的网络配置，为了表示确实是两个容器，用ll命令查看了各自当前目录下的文件，

1e5c62d8e949容器网络配置：

![](Docker—网络模式\1e5c62d8e949.png)

5f10383b6052容器网络配置：

![](Docker—网络模式\5f10383b6052.png)

可以看到2个容器网络配置确实一模一样。

结构图：

![](Docker—网络模式\container.png)

### None模式

使用none模式，Docker容器拥有自己的Network Namespace，但是，并不为Docker容器进行任何网络配置。也就是说，这个Docker容器没有网卡、IP、路由等信息。需要我们自己为Docker容器添加网卡、配置IP等。

创建container模式容器命令如下：

```
docker run -it  --net=none centos /bin/bash
```

查看宿主机信息：

![](Docker—网络模式\none-host.png)

容器无法和docker0通信，而且/etc/hosts中没有ip的配置：

![](Docker—网络模式\none-ping.png)

node模式结构图：

![](Docker—网络模式\none.png)

现在这个容器没有ip地址，如何给他分配一个ip？

docker是借助于cGroup和namespace技术来实现资源控制和隔离的，关于这2个技术这里不讲解。

docker通过namespace设置网络过程：

1、创建一个Net Namespace  netns-demo

2、创建一对veth pair，将一端vethxxx加入到netns-demo，将别一端接入到网桥bridge-demo中

3、为这两个veth虚拟设备分配IP

4、用netns-demo启动容器中的程序比如/bin/bash

我们来看看上面那个容器的net  namespace

```
# 查看当前所有Net Namespace，但是发现并没有上面输出，原因是docker为了抹掉细节，删除了/var/run/netns/下的信息
root@ubuntu:~# ip netns list
# 查看容器pid
root@ubuntu:~# docker inspect -f '{{.State.Pid}}' b283bc06185f
4761
# 将netns打回原形
root@ubuntu:~# ln -s /proc/4761/ns/net /var/run/netns/4761
ln -s /proc/pid值/ns/net /var/run/netns/pid值（也可以是其他描述信息）
# 再通过 ip netns list查看
root@ubuntu:~# ip netns list
4761

```

下面我们来看看分配给容器静态ip的过程：

1、用--net=none方式启动容器

![](Docker—网络模式\none-run.png)

2、docker inspect 获取容器的进程号PID，根据PID将它的Net Namespace打回原型

![](Docker—网络模式\none-ln.png)

3、创建一个bridge-demo，用brctl工具

![](Docker—网络模式\none-create-br.png)

4、创建一对veth pair：vethBridge，vethContainer，将peer端vethContainer加入到窗口的Net Namespace中，将vethBridge接入到bridge-demo中，设置vethContainer的IP

![](Docker—网络模式\none-con-ip.png)

5、查看容器ip

![](Docker—网络模式\none-co-ifconfig.png)

现在已经给这个容器设置了ip，但是现在仍然不能与主机其他网卡通信



