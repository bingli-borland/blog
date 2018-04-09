---
title: Tomcat源码分析—Bootstrap启动和停止
date: 2018-04-07 12:50:56
tags: [tomcat, bootstrap, java, server]
categories: [tomcat]
---

### 前言

根据前面的分析，通过startup.bat脚本可以启动tomcat，通过shutdown.bat脚本可以停止tomcat，那究竟在启动和停止过程中做了哪些事？本篇我们来通过debug分析下

### 调试入口在哪儿

如何找到调式的入口类，一直方式时直接去看bin下catalina和startup脚本，这里我们采用另一种方式，启动tomcat，然后通过jps命令查看返回信息，如下

```powershell
E:\project\TOMCAT_7_0_83\output\build\bin>jps -lmv
14148 org.apache.catalina.startup.Bootstrap start -Djava.util.logging.config.file=E:\project\TOMCAT_7_0_83\output\build\conf\logging.properties -Djava.util.logging.manager=org.apache.juli.ClassLoaderLogManager -Djdk.tls.ephemeralDHKeySize=2048 -Dignore.endorsed.dirs= -Dcatalina.base=E:\project\TOMCAT_7_0_83\output\build -Dcatalina.home=E:\project\TOMCAT_7_0_83\output\build -Djava.io.tmpdir=E:\project\TOMCAT_7_0_83\output\build\temp
```

<!--more-->

可以看到**org.apache.catalina.startup.Bootstrap start**这条信息，很明显main函数就在Bootstarp类中，start是它的参数，这就是我们找到的入口，下面在eclipse中debug启动过程。

### 启动

首先我们来看main函数

![](Tomcat源码分析—Bootstrap启动与停止\bootstrap-main.jpg)

bootstrap.init()做了什么？

```java
public void init() throws Exception {
    // 1.设置tomcat安装目录
    setCatalinaHome();
    // 2.设置tomcat实例目录
    setCatalinaBase();
	// 3.初始化classloader，并作为当前线程的上下文classloader
    initClassLoaders();
    Thread.currentThread().setContextClassLoader(catalinaLoader);
    SecurityClassLoad.securityClassLoad(catalinaLoader);

    if (log.isDebugEnabled())
        log.debug("Loading startup class");
    Class<?> startupClass=catalinaLoader.loadClass("org.apache.catalina.startup.Catalina");
    // 4.反射创建tomcat重量级对象catalina,后面的启动都靠它来管理
    Object startupInstance = startupClass.newInstance();

    if (log.isDebugEnabled())
        log.debug("Setting startup class properties");
    String methodName = "setParentClassLoader";
    Class<?> paramTypes[] = new Class[1];
    paramTypes[0] = Class.forName("java.lang.ClassLoader");
    Object paramValues[] = new Object[1];
    paramValues[0] = sharedLoader;
    Method method = startupInstance.getClass().getMethod(methodName, paramTypes);
    // 5.反射调用Catalina的setParentClassLoader方法设置父类加载器（并不是classloader中真正意义的parentClassloader）
    method.invoke(startupInstance, paramValues);
    catalinaDaemon = startupInstance;
}
```

daemon.load(args)和daemon.start()做了什么？

```java
private void load(String[] arguments) throws Exception {
    // Call the load() method
    String methodName = "load";
    Object param[];
    Class<?> paramTypes[];
    if (arguments==null || arguments.length==0) {
        paramTypes = null;
        param = null;
    } else {
        paramTypes = new Class[1];
        paramTypes[0] = arguments.getClass();
        param = new Object[1];
        param[0] = arguments;
    }
    Method method =
        catalinaDaemon.getClass().getMethod(methodName, paramTypes);
    if (log.isDebugEnabled())
        log.debug("Calling startup class " + method);
    // 6.反射调用Catalina对象的load方法
    method.invoke(catalinaDaemon, param);
}

public void start()
    throws Exception {
    if( catalinaDaemon==null ) init();
    Method method = catalinaDaemon.getClass().getMethod("start", (Class [] )null);
    // 7. 反射调用Catalina对象的start方法
    method.invoke(catalinaDaemon, (Object [])null);
}
```



#### 设置tomcat安装目录和实例目录

![](Tomcat源码分析—Bootstrap启动与停止\catalina-home.jpg)

setCatalinaBase这里就不分析了，和setCatalinaHome类似

#### 初始化Classloader

首先我们看看tomcat的classloader层次，再看代码就比较清晰了

```
      Bootstrap
          |
       System
          |
       Common
      /      \
 Catalina   Shared
             /   \
        Webapp1  Webapp2 ...
```

![](Tomcat源码分析—Bootstrap启动与停止\init-classloader.jpg)

ClassLoaderFactory.createClassLoader主要是对repositories（jar、url、dir、glob）做一些校验、转换（例：F:\\dir\\test.jar转成URL形式 file:/F:/dir/test.jar），创建URLClassLoader返回。默认情况下，最终初始化完成之后，catalinaLoader和sharedLoader都指向commonLoader指向的ClassLoader对象，即实际上只存在commonLoader，因为查看catalina.properties文件以及根据上面的分析，server.loader和shared.loader是没有配置任何信息的，如下图：

![](Tomcat源码分析—Bootstrap启动与停止\catalina-prop.jpg)

#### 创建Catalina对象

通过catalinaLoader加载org.apache.catalina.startup.Catalina类，然后反射创建对象，最后反射调用catalina对象的setParentClassLoader方法设置sharedLoader给catalina对象的 parentClassLoader属性（类型为ClassLoader），最后catalinaDaemon引用指向catalina对象。

#### Catalina.load

创建完catalina对象之后，先通过Bootstrap.load反射调用Catalina.load方法，下面来看看里面做了什么事

![](Tomcat源码分析—Bootstrap启动与停止\catalina-load.jpg)

其中getServer().init()会顺着tomcat生命周期机制执行子组件的init方法

#### Catalina.start

通过Bootstrap.start反射调用Catalina.start方法，下面来看看这里面又做了什么事

![](Tomcat源码分析—Bootstrap启动与停止\catalina-start.jpg)

而实际上await方法调用的时Server的await方法，看看代码逻辑:

```java
public void await() {
        // Negative values - don't wait on port - tomcat is embedded or we just don't like ports
        if( port == -2 ) {
            // undocumented yet - for embedding apps that are around, alive.
            return;
        }
        if( port==-1 ) {
            try {
                awaitThread = Thread.currentThread();
                // 通过stopAwait标志确定是否退出主线程
                while(!stopAwait) {
                    try {
                        Thread.sleep( 10000 );
                    } catch( InterruptedException ex ) {
                        // continue and check the flag
                    }
                }
            } finally {
                awaitThread = null;
            }
            return;
        }

        // 创建ServeSocket监听关闭请求
        try {
            awaitSocket = new ServerSocket(port, 1,
                    InetAddress.getByName(address));
        } catch (IOException e) {
            log.error("StandardServer.await: create[" + address
                               + ":" + port
                               + "]: ", e);
            return;
        }

        try {
            awaitThread = Thread.currentThread();
            // Loop waiting for a connection and a valid command
            while (!stopAwait) {
                ServerSocket serverSocket = awaitSocket;
                if (serverSocket == null) {
                    break;
                }
                // Wait for the next connection
                Socket socket = null;
                StringBuilder command = new StringBuilder();
                try {
                    InputStream stream;
                    long acceptStartTime = System.currentTimeMillis();
                    try {
                        socket = serverSocket.accept();
                        socket.setSoTimeout(10 * 1000);  // Ten seconds
                        stream = socket.getInputStream();
                    } catch (SocketTimeoutException ste) {
                        // This should never happen but bug 56684 suggests that
                        // it does.
                        log.warn(sm.getString("standardServer.accept.timeout",
                                Long.valueOf(System.currentTimeMillis() - acceptStartTime)), ste);
                        continue;
                    } catch (AccessControlException ace) {
                        log.warn("StandardServer.accept security exception: "
                                + ace.getMessage(), ace);
                        continue;
                    } catch (IOException e) {
                        if (stopAwait) {
                            // Wait was aborted with socket.close()
                            break;
                        }
                        log.error("StandardServer.await: accept: ", e);
                        break;
                    }

                    // Read a set of characters from the socket
                    int expected = 1024; // Cut off to avoid DoS attack
                    while (expected < shutdown.length()) {
                        if (random == null)
                            random = new Random();
                        expected += (random.nextInt() % 1024);
                    }
                    while (expected > 0) {
                        int ch = -1;
                        try {
                            ch = stream.read();
                        } catch (IOException e) {
                            log.warn("StandardServer.await: read: ", e);
                            ch = -1;
                        }
                        // Control character or EOF (-1) terminates loop
                        if (ch < 32 || ch == 127) {
                            break;
                        }
                        command.append((char) ch);
                        expected--;
                    }
                } finally {
                    // Close the socket now that we are done with it
                    try {
                        if (socket != null) {
                            socket.close();
                        }
                    } catch (IOException e) {
                        // Ignore
                    }
                }

                // Match against our command string
                boolean match = command.toString().equals(shutdown);
                if (match) {
                    log.info(sm.getString("standardServer.shutdownViaPort"));
                    break;
                } else
                    log.warn("StandardServer.await: Invalid command '"
                            + command.toString() + "' received");
            }
        } 
    }
```

总结上面的await方法就是以下几点：

```
port等于-2，则直接退出，不进入循环
port等于-1，进入一个while循环，没有break跳出循环，只能通过stopAwait标志来退出，stopAwait只有调用了stop方法才会设置为true
port为其他值，会进入一个while循环，同时会有一个ServerSocket来监听port端口，如果接收到SHUTDOWN命令，则跳出循环
```

整个启动的流程如下：

![](Tomcat源码分析—Bootstrap启动与停止\bootstrap.png)

初始化init和启动start流程如下：

![](Tomcat源码分析—Bootstrap启动与停止\lifecycle.png)

### 停止

分析完大致的启动流程，我们来看看执行shutdown脚本停止tomcat时又是如何实现的，按照同样的方法我们可以找到停止tomcat的入口类同样是Bootstrap，而且根据Bootstrap.main方法可以知道，停止tomcat的主要实现就是在Bootstrap.stopServer方法中，实际上还是反射调用Catalina的stopServer方法，来看代码：

![](Tomcat源码分析—Bootstrap启动与停止\catalina-stop.jpg)

