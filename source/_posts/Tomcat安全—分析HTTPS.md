---
title: Tomcat安全—分析HTTPS
date: 2018-05-13 22:28:56
updated: 2018-05-13 22:28:56
tags: [tomcat, https, java, wireshark]
categories: [tomcat]
---

### 前言

上一篇文章已经讲了如何给tomcat配置https，证书制作等，本篇使用协议分析工具深入理解https，看看https握手的过程以及可能出现的问题，使用的环境：

win10 x64

CentOS7.3 x64

Wireshark Version 2.6.0 (v2.6.0-0-gc7239f02)  [下载地址](https://www.wireshark.org/download/win64/all-versions/ )

<!--more-->

### 报文抓取

#### HTTP

首先我们来看一下，在不配置安全的情况下，http请求和响应的报文是如何的？这里由于我们是本地访问，因此无法使用wireshark抓取Loopback接口的数据包，因此需要用到linux的tcpdump命令来抓取数据。注意需要root用户。那么在上篇的环境下，启动tomcat，打开命令行执行如下命令：

```shell
#查看help信息
[root@k8s-master ~]# tcpdump --help
tcpdump version 4.9.0
libpcap version 1.5.3
OpenSSL 1.0.1e-fips 11 Feb 2013
Usage: tcpdump [-aAbdDefhHIJKlLnNOpqStuUvxX#] [ -B size ] [ -c count ]
                [ -C file_size ] [ -E algo:secret ] [ -F file ] [ -G seconds ]
                [ -i interface ] [ -j tstamptype ] [ -M secret ] [ --number ]
                [ -Q|-P in|out|inout ]
                [ -r file ] [ -s snaplen ] [ --time-stamp-precision precision ]
                [ --immediate-mode ] [ -T type ] [ --version ] [ -V file ]
                [ -w file ] [ -W filecount ] [ -y datalinktype ] [ -z postrotate-command ]
                [ -Z user ] [ expression ]
-i 指定网卡接口
-w 写入数据包的文件名
expression 过滤数据包的表达式

# 开启一个终端，执行如下命令：抓取经过网卡eno16777736的，地址为192.168.1.110 端口为8080的数据，并写入文件http.pcap
[root@k8s-master ~]# tcpdump -i eno16777736 host 192.168.1.110 and port 8080 -w http.pcap
# 另开一个终端，访问tomcat
[root@k8s-master ~]# curl 'http://192.168.1.110:8080/examples/servlets/servlet/RequestParamExample'
```

在生成http.pcap文件，拷贝到windows后，用wireshark打开http.pcap文件：
![](http.jpg)

***数据包1-3***：很明显这是tcp协议3次握手建立连接的数据包

***数据包4-5***：http请求和响应的数据包，右键点击数据包4-->追踪流-->HTTP流：
![](http-detail.jpg)

可以看到，红色部分为http请求数据，蓝色部分为http的响应

***数据包6***：客户端对收到数据包5的确认

***数据包7-10***：tcp协议4次挥手断开连接的数据包

#### HTTPS

这里有一些概念，https握手实际为SSL/TLS握手过程，可以分成两种类型：

> 1）SSL/TLS 双向认证，就是双方都会互相认证，也就是两者之间将会交换证书。
>
> 2）SSL/TLS 单向认证，客户端会认证服务器端身份，而服务器端不会去对客户端身份进行验证。

SSL/TLS协议的基本思路是采用公钥加密，即客户端先向服务器端索要公钥，然后用公钥加密信息，服务器收到密文后，用自己的私钥解密。但是存在两个问题，

**（1）如何保证公钥不被篡改？**

> 解决方法：将公钥放在数字证书中。只要证书是可信的，公钥就是可信的，而数字证书的安全性又由CA认证中心来保证

**（2）公钥加密计算量太大，如何减少耗用的时间？**

> 解决方法：每一次对话（session），客户端和服务器端都生成一个"对话密钥"（session key），用它来加密信息。由于"对话密钥"是对称加密，所以运算速度非常快，而服务器公钥只用于加密"对话密钥"本身，这样就减少了加密运算的消耗时间。实际上https具体请求和响应的内容就是用的对话密钥加密解密的

上面我们已经启动了tomcat，8443端口就是需要https访问的端口，这里我们为了排除浏览器干扰，决定使用java写一个客户端程序访问https，代码如下：

```java
import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.UnsupportedEncodingException;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.KeyManagementException;
import java.security.KeyStore;
import java.security.KeyStoreException;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.security.UnrecoverableKeyException;
import java.security.cert.CertificateException;
import java.util.List;
import java.util.Map;

import javax.net.ssl.HostnameVerifier;
import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.KeyManager;
import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSession;
import javax.net.ssl.TrustManager;
import javax.net.ssl.TrustManagerFactory;

public class HttpsTest {
    // 客户端证书
    public static String KEY_STORE_FILE = "/root/client.p12";
    // 客户端证书密码
    public static String KEY_STORE_PASS = "changeit";
    // 客户端证书信任库
    public static String TRUST_STORE_FILE = "/root/cacerts.jks";
    // 客户端证书信任库密码
    public static String TRUST_STORE_PASS = "changeit";

    private static SSLContext sslContext;

    /**
     * 向指定URL发送GET方法的请求
     * 
     * @param url
     *            发送请求的URL
     * @param param
     *            请求参数，请求参数应该是 name1=value1&name2=value2 的形式。
     * @return URL 所代表远程资源的响应结果
     * 
     */
    public static String sendGet(String url, String param) {
        String result = "";
        BufferedReader in = null;
        try {
            String urlNameString = url + "?" + param;
            URL realUrl = new URL(urlNameString);
            // 打开和URL之间的连接
            HttpURLConnection connection = (HttpURLConnection) realUrl.openConnection();
            // 如果connection是HttpsConnection，则设置SSLContext
            if (connection instanceof HttpsURLConnection) {
                ((HttpsURLConnection) connection).setSSLSocketFactory(getSSLContext().getSocketFactory());
            }

            // 设置通用的请求属性
            connection.setRequestProperty("accept", "*/*");
            connection.setRequestProperty("connection", "Keep-Alive");
            connection.setRequestProperty("user-agent", "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1;SV1)");
            // 建立实际的连接
            connection.connect();
            // 获取所有响应头字段
            Map<String, List<String>> map = connection.getHeaderFields();
            // 遍历所有的响应头字段
            for (String key : map.keySet()) {
                System.out.println(key + "--->" + map.get(key));
            }
            // 定义 BufferedReader输入流来读取URL的响应

            if (connection.getResponseCode() == 200) {
                in = new BufferedReader(new InputStreamReader(connection.getInputStream()));
            } else {
                in = new BufferedReader(new InputStreamReader(connection.getErrorStream()));
            }
            String line;
            while ((line = in.readLine()) != null) {
                result += line;
            }

        } catch (Exception e) {
            System.out.println("发送GET请求出现异常！" + e);
            e.printStackTrace();
        }
        // 使用finally块来关闭输入流
        finally {
            try {
                if (in != null) {
                    in.close();
                }
            } catch (Exception e2) {
                e2.printStackTrace();
            }
        }
        return result;
    }

    public static SSLContext getSSLContext() {
        long time1 = System.currentTimeMillis();
        if (sslContext == null) {
            try {
                KeyManagerFactory kmf = KeyManagerFactory.getInstance("SunX509");
                kmf.init(getkeyStore(), KEY_STORE_PASS.toCharArray());
                KeyManager[] keyManagers = kmf.getKeyManagers();

                TrustManagerFactory trustManagerFactory = TrustManagerFactory.getInstance("SunX509");
                trustManagerFactory.init(getTrustStore());
                TrustManager[] trustManagers = trustManagerFactory.getTrustManagers();

                sslContext = SSLContext.getInstance("TLS");
                sslContext.init(keyManagers, trustManagers, new SecureRandom());
                HttpsURLConnection.setDefaultHostnameVerifier(new HostnameVerifier() {
                    @Override
                    public boolean verify(String hostname, SSLSession session) {
                        // 校验证书上的网址和访问的是否一致
                        return true;
                    }
                });
            } catch (FileNotFoundException e) {
                e.printStackTrace();
            } catch (NoSuchAlgorithmException e) {
                e.printStackTrace();
            } catch (IOException e) {
                e.printStackTrace();
            } catch (UnrecoverableKeyException e) {
                e.printStackTrace();
            } catch (KeyStoreException e) {
                e.printStackTrace();
            } catch (KeyManagementException e) {
                e.printStackTrace();
            }
        }
        long time2 = System.currentTimeMillis();
        System.out.println("SSLContext 初始化时间：" + (time2 - time1));
        return sslContext;
    }

    /**
     * 获取证书KeyStore
     * 
     * @return
     */
    public static KeyStore getkeyStore() {
        KeyStore keySotre = null;
        try {
            // client.p12证书类型是PKCS12
            keySotre = KeyStore.getInstance("PKCS12");
            FileInputStream fis = new FileInputStream(new File(KEY_STORE_FILE));
            keySotre.load(fis, KEY_STORE_PASS.toCharArray());
            fis.close();
        } catch (KeyStoreException e) {
            e.printStackTrace();
        } catch (FileNotFoundException e) {
            e.printStackTrace();
        } catch (NoSuchAlgorithmException e) {
            e.printStackTrace();
        } catch (CertificateException e) {
            e.printStackTrace();
        } catch (IOException e) {
            e.printStackTrace();
        }
        return keySotre;
    }

    /**
     * 获取信任库TrustStore
     * 
     * @return
     * @throws IOException
     */
    public static KeyStore getTrustStore() throws IOException {
        KeyStore trustKeyStore = null;
        FileInputStream fis = null;
        try {
            // cacert.jks的证书类型是JKS
            trustKeyStore = KeyStore.getInstance("JKS");
            fis = new FileInputStream(new File(TRUST_STORE_FILE));
            trustKeyStore.load(fis, TRUST_STORE_PASS.toCharArray());
        } catch (FileNotFoundException e) {
            e.printStackTrace();
        } catch (KeyStoreException e) {
            e.printStackTrace();
        } catch (NoSuchAlgorithmException e) {
            e.printStackTrace();
        } catch (CertificateException e) {
            e.printStackTrace();
        } catch (IOException e) {
            e.printStackTrace();
        } finally {
            fis.close();
        }
        return trustKeyStore;
    }

    public static void main(String[] args) throws UnsupportedEncodingException {
        // 设置TLS版本
        System.setProperty("https.protocols", "TLSv1.2");
        String result = sendGet("https://www.bingli.com:8443/examples/servlets/servlet/RequestParamExample", "a=x1");
        System.out.println(result);
    }
}

```

wireshark中设置抓包规则，port  8443，然后在Linux下运行这段代码，抓取到的数据包如下：

![](https-all.jpg)

ssl/tls握手的主要流程入下：

| Client                                                       | Server                                                       |
| :----------------------------------------------------------- | :----------------------------------------------------------- |
| 1 Client Hello                                               |                                                              |
|                                                              | 2 Server Hello <br>3 certificate<br><font color="red">4 (server_key_exchange)</font><br><font color="red">5 (certificate_request)</font><br>6 server_hello_done |
| <font color="red">7 (certificate)</font><br>8 client_key_exchange<br><font color="red">9 (certifiate_verify)</font><br>10 change_cypher_spec<br>11 Encrypted Handshake Message |                                                              |
|                                                              | 12 change_cypher_spec<br>13 Encrypted Handshake Message      |

**第一步是客户端向服务端发送消息：**

![](https-client-hello.jpg)

##### Client Hello

客户端向服务端发送 Client Hello 消息，这个消息里包含了

（1）采用的协议版本，比如TLS 1.2

（2）客户端生成的随机数Random1，稍后用于生成"对话密钥"

（3）客户端支持的加密算法(Support Ciphers)



**第二步服务器回答给客户端以下信息 ：**

![](https-server-hello.jpg)

##### Server Hello

此消息中包含如下信息：

（1） 确认使用的协议版本

（2） 服务端生成的随机数Random2，客户端和服务端都拥有了两个随机数（Random1+ Random2），这两个随机数会在后续生成“对话秘钥”时用到 

（3） session id

（4） 确认使用的加密套件，根据从 Client Hello 传过来的 Support Ciphers 里确定一份加密套件 ，例如

> Cipher Suite: TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256 (0xc02f)
>
> ECDHE : 密钥交换算法，用于生成premaster_secret（用于生成会话密钥master secret） 
>
> RSA : 签名算法，用户安全传输premaster_secret 
>
> AES_128 : 连接建立后的数据加密算法 
>
> GCM : 一种对称密钥加密操作的块密码模式 

##### Certificate（Server）

此消息服务端将自己的证书下发给客户端，让客户端验证自己的身份，客户端验证通过后取出证书中的公钥，具体信息如下：

![](https-server-certificate.jpg)

可以看到这就是我们在上篇文章里创建的服务端证书信息。

##### Server Key Exchange 

只有在客户端与服务器端双方协商采用的加密算法是DHE_DSS、DHE_RSA、DH_anon时Server Certificate消息中的服务器证书中的信息不足以生成premaster secret时服务器端才需要发送此消息 															

##### Certificate Request 

此信息表示要求客户端提供证书，当开启客户端验证即使用了双向认证的时候会发送此消息。主要包括

（1） 客户端可以提供的证书类型

（2）服务器接受的证书distinguished name列表，可以是root CA或者subordinate CA。如果服务器配置了trust keystore, 这里会列出所有在trust keystore中的证书的distinguished name。

![](httpsr-certificate-req.jpg)

可以看到这就是我们在上篇文章里创建的信任库cacerts.jks中证书信息

##### Server Hello Done

Server Hello Done 通知客户端 Server Hello 过程结束 

**第三步是客户端继续向服务端发送消息：**

![](https-client-certificate.jpg)

##### Certificate（Client）

当服务端开启客户端验证的情况下，客户端将会把客户端证书发送给服务端，从上图中可以看到正是客户端证书client.p12的信息

##### Client Key Exchange

客户端根据服务器传来的公钥生成了 **Pre Master Secret**，Client Key Exchange 就是将这个 key 传给服务端，服务端再用自己的私钥解出这个 **PreMaster Secret** 得到客户端生成的 **Random3**。至此，客户端和服务端都拥有 **Random1** + **Random2** + **Random3**，两边再根据同样的算法就可以生成对话密钥Master Secret，握手结束后的应用层数据都是使用这个对话秘钥进行对称加密和解密。

> **RSA** ：*premaster_secret*是由客户端生成的随机数，用服务器证书中公钥加密后传输，服务器端采用私钥解密。
>
> **Diffie-Hellman**： 对于*Diffie-Hellman*算法而言，双方通过*Server Key Exchange Message* 与 *Client Key Exchange Message* 交换两个数即可各自算出相同的加密密钥，用此当**premaster_secret**

##### Certificate Verify

在服务端开启了客户端验证的情况下，客户端会发送此消息给服务端，其中携带到这一步为止收到和发送的所有握手消息用客户端证书私钥所做的签名，服务器收到此信息可利用公钥验证，是典型的数字签名验证场景。 

##### Change Cipher Spec（Client）

客户端生成**master secret**之后即可发送通知给服务器端，以后要使用对称密钥**master secret**来加密数据了！客户端使用上面的3个随机数client random, server random, pre-master secret, 计算出48字节的master secret, 这个就是对称加密算法的密钥。

##### Encrypt  Hanshake Message（Client）

客户端发送握手结束通知，同时会带上前面发送和接受内容的签名到服务器端，保证前面通信数据的正确性 

**第四步是服务端向客户端发送消息：**

##### Change Cipher Spec（Server）

服务端生成**master secret**之后即可发送通知给客户端，以后要使用对称密钥**master secret**来加密数据了

##### Encrypt  Hanshake Message（Server）

服务端发送握手结束通知，同时会带上前面发送和接受内容的签名到客户端，保证前面通信数据的正确性 

***整个握手过程可以参考[RFC5246](https://tools.ietf.org/html/rfc5246)文档***

#### HTTPS单向认证

上面讲的是双向认证的报文分析，那么如果是单向认证，报文如何，是否为上面分析的那样？我们实验一下，修改tomcat的配置：

```xml
<Connector port="8443" protocol="org.apache.coyote.http11.Http11Protocol"
    maxThreads="150" SSLEnabled="true" scheme="https" secure="true" 
    keystoreFile="conf/mykeystore" keystorePass="changeit" keyAlias="bingli"
    clientAuth="false" sslProtocol="TLS" />
```

启动tomcat后还是相同的抓包方式，相同的访问方式，抓取到的报文如下：

![](https-alone.jpg)

可以看到，https单项认证确实比双向认证少了Certificate Request、Certificate（Client）、Certificate Verify过程。

### java实现ssl通信

基本代码如下：

```java
import java.io.BufferedReader;  
import java.io.FileInputStream;  
import java.io.IOException;  
import java.io.InputStreamReader;  
import java.io.PrintWriter;  
import java.net.ServerSocket;  
import java.net.Socket;  
import java.security.KeyStore;  
  
import javax.net.ServerSocketFactory;  
import javax.net.ssl.KeyManagerFactory;  
import javax.net.ssl.SSLContext;  
import javax.net.ssl.SSLServerSocket;  
  
public class SSLServer extends Thread {  
    private Socket socket;  
  
    public SSLServer(Socket socket) {  
        this.socket = socket;  
    }  
  
    public void run() {  
        try {  
            BufferedReader reader = new BufferedReader(new InputStreamReader(socket.getInputStream()));  
            PrintWriter writer = new PrintWriter(socket.getOutputStream());  
  
            String data = reader.readLine();  
            writer.println(data);  
            writer.close();  
            socket.close();  
        } catch (IOException e) {  
  
        }  
    }  
  
    private static String SERVER_KEY_STORE = "E:\\project\\TOMCAT_7_0_83\\output\\build\\conf\\mykeystore";  
    private static String SERVER_KEY_STORE_PASSWORD = "changeit";  
  
    public static void main(String[] args) throws Exception {  
        System.setProperty("javax.net.ssl.trustStore", SERVER_KEY_STORE);  
        SSLContext context = SSLContext.getInstance("TLS");  
          
        KeyStore ks = KeyStore.getInstance("jks");  
        ks.load(new FileInputStream(SERVER_KEY_STORE), null);  
        KeyManagerFactory kf = KeyManagerFactory.getInstance("SunX509");  
        kf.init(ks, SERVER_KEY_STORE_PASSWORD.toCharArray());  
          
        context.init(kf.getKeyManagers(), null, null);  
  
        ServerSocketFactory factory = context.getServerSocketFactory(); 
        // 创建安全的ServerSocket套接字
        ServerSocket _socket = factory.createServerSocket(8443);  
        // 是否开启客户端认证
        ((SSLServerSocket) _socket).setNeedClientAuth(false);  
  
        while (true) {  
            new SSLServer(_socket.accept()).start();  
        }  
    }  
}  
```

这样，基本的安全通信就写好了，其实tomcat的https原理也就是这样，只不过他做了一些封装，比如我们来看看org.apache.tomcat.util.net.jsse.JSSESocketFactory这个类，它实现了上面的ServerSocketFactory接口，构造函数如下和初始化方法：

```java
public JSSESocketFactory (AbstractEndpoint<?> endpoint) {
    this.endpoint = endpoint;

    String sslProtocol = endpoint.getSslProtocol();
    if (sslProtocol == null) {
        sslProtocol = defaultProtocol;
    }

    SSLContext context;
    try {
        context = SSLContext.getInstance(sslProtocol);
        context.init(null,  null,  null);
    } catch (NoSuchAlgorithmException e) {
        // This is fatal for the connector so throw an exception to prevent
        // it from starting
        throw new IllegalArgumentException(e);
    } catch (KeyManagementException e) {
        // This is fatal for the connector so throw an exception to prevent
        // it from starting
        throw new IllegalArgumentException(e);
    }

    // Supported cipher suites aren't accessible directly from the
    // SSLContext so use the SSL server socket factory
    SSLServerSocketFactory ssf = context.getServerSocketFactory();
    String supportedCiphers[] = ssf.getSupportedCipherSuites();
    boolean found = false;
    for (String cipher : supportedCiphers) {
        if ("TLS_EMPTY_RENEGOTIATION_INFO_SCSV".equals(cipher)) {
            found = true;
            break;
        }
    }
    rfc5746Supported = found;

    // There is no standard way to determine the default protocols and
    // cipher suites so create a server socket to see what the defaults are
    SSLServerSocket socket;
    try {
        socket = (SSLServerSocket) ssf.createServerSocket();
    } catch (IOException e) {
        // This is very likely to be fatal but there is a slim chance that
        // the JSSE implementation just doesn't like creating unbound
        // sockets so allow the code to proceed.
        defaultServerCipherSuites = new String[0];
        defaultServerProtocols = new String[0];
        log.warn(sm.getString("jsse.noDefaultCiphers", endpoint.getName()));
        log.warn(sm.getString("jsse.noDefaultProtocols", endpoint.getName()));
        return;
    }
    ....
}

/**
  * Reads the keystore and initializes the SSL socket factory.
  */
void init() throws IOException {
    try {

        String clientAuthStr = endpoint.getClientAuth();
        if("true".equalsIgnoreCase(clientAuthStr) ||
           "yes".equalsIgnoreCase(clientAuthStr)) {
            requireClientAuth = true;
        } else if("want".equalsIgnoreCase(clientAuthStr)) {
            wantClientAuth = true;
        }

        SSLContext context = createSSLContext();
        context.init(getKeyManagers(), getTrustManagers(), null);

        // Configure SSL session cache
        SSLSessionContext sessionContext =
            context.getServerSessionContext();
        if (sessionContext != null) {
            configureSessionContext(sessionContext);
        }

        // create proxy
        sslProxy = context.getServerSocketFactory();

        // Determine which cipher suites to enable
        enabledCiphers = getEnableableCiphers(context);
        enabledProtocols = getEnableableProtocols(context);

        allowUnsafeLegacyRenegotiation = "true".equals(
            endpoint.getAllowUnsafeLegacyRenegotiation());

        // Check the SSL config is OK
        checkConfig();

    } catch(Exception e) {
        if( e instanceof IOException )
            throw (IOException)e;
        throw new IOException(e.getMessage(), e);
    }
}
```

是不是和上面的代码很像，关键就是SSLContext这个上下文，获取到的ServerSocketFactory的实现是SSLServerSocketFactory。好了本文到此为止，如果有一些报文分析的案例，后面会补充到这里。

