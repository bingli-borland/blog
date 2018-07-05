---
title: Tomcat源码分析—应用部署分析(一)
date: 2018-07-04 15:11:03
updated: 2018-07-04 15:11:03
tags: [tomcat, deploy, java]
categories: [tomcat]
---

### 前言

前面已经分析过了tomcat的启动和配置解析，但是作为一款应用服务器，最重要的是能部署应用，接下来探究tomcat如何完成应用部署以及资源加载的？

### 源码

#### server.xml中配置Context元素

配置如下：

```xml
<Host name="localhost"  appBase="webapps"
            unpackWARs="true" autoDeploy="true">
	<Context docBase="E:\project\tomcat\webapps1\manager" path="test222"/>
        <Valve className="org.apache.catalina.valves.AccessLogValve" directory="logs"
               prefix="localhost_access_log" suffix=".txt"
               pattern="%h %l %u %t &quot;%r&quot; %s %b" />
</Host>
```
<!-- more -->

Context可以配置的属性集合：

> path：是访问时的根地址，比如上面的应用访问路径为`http://localhost:8080/test222`，如果指定空字符串（“”）的上下文路径，则表示您正在为此主机定义默认Web应用程序，该应用程序将处理未分配给其他上下文的所有请求。  只有在server.xml中静态定义Context时，才能使用此属性。 在所有其他情况下，将从用于.xml上下文文件或docBase的文件名推断出该路径。  即使在server.xml中静态定义Context，也不能设置此属性，除非docBase不在Host的appBase下，或者deployOnStartup和autoDeploy都为false
>
> reloadable：表示WebappLoader可以在运行时在backgroundProcess方法中判断classes与lib文件夹放生改变时是否重加载
>
> docBase：表示应用程序的路径。docBase可以使用绝对路径，也可以使用相对路径，相对路径相对于webapps
>
> workDir：应用的工作目录，存放运行时生成的文件
>
> debug：设定debug level, 0表示提供最少的信息，9表示提供最多的信息。
>
> privileged：设置为true的时候，web应用使用容器内的Servlet。

由于digester解析规则配置Host元素下解析Context元素，tomcat启动时，会将Context构建成StandardContext对象通过addChild添加给Host，并且启动了Context，在此过程中解析web.xml等，应用成功部署，且默认没有任何日志输出。

#### 自定义部署文件

此文件一般放在${catalina.base}/conf/engine name/host name目录下，例如conf\Catalina\localhost\ROOT.xml内容如下：

```xml
<Context docBase='E:\project\tomcat\webapps1\manager'/>
```

此方式和上面的方式差不多，且不需要配置path，配置了也不起作用 （根据上面对path的解释），但是此种方式涉及到一个重要的类HostConfig，继承自LifecyceListener，这个类同样是digester解析规则配置Host元素时，通过LifecycleListenerRule添加给Host的一个监听器。

#### HostConfig

HostConfig随着Host的启动触发其lifecycleEvent方法。如下：

```java
@Override
public void lifecycleEvent(LifecycleEvent event) {
	// Identify the host we are associated with
	try {
	    host = (Host) event.getLifecycle();
	    if (host instanceof StandardHost) {
	        setCopyXML(((StandardHost) host).isCopyXML());
	        setDeployXML(((StandardHost) host).isDeployXML());
	        setUnpackWARs(((StandardHost) host).isUnpackWARs());
	        setContextClass(((StandardHost) host).getContextClass());
	    }
	} catch (ClassCastException e) {
	    log.error(sm.getString("hostConfig.cce", event.getLifecycle()), e);
	    return;
	}

	// Process the event that has occurred
	if (event.getType().equals(Lifecycle.PERIODIC_EVENT)) {
	    check();
	} else if (event.getType().equals(Lifecycle.START_EVENT)) {
	    start();
	} else if (event.getType().equals(Lifecycle.STOP_EVENT)) {
	    stop();
	}
}
```

随后会调用start方法，并在start方法中判断host的deployOnStartup属性是否为true，进而确定是否要部署应用：

```java
public void start() {
	if (host.getCreateDirs()) {
	    File[] dirs = new File[] {host.getAppBaseFile(),host.getConfigBaseFile()};
	    for (int i=0; i<dirs.length; i++) {
	        if (!dirs[i].mkdirs() && !dirs[i].isDirectory()) {
	            log.error(sm.getString("hostConfig.createDirs",dirs[i]));
	        }
	    }
	}

	if (!host.getAppBaseFile().isDirectory()) {
	    log.error(sm.getString("hostConfig.appBase", host.getName(),
	            host.getAppBaseFile().getPath()));
	    host.setDeployOnStartup(false);
	    host.setAutoDeploy(false);
	}

	if (host.getDeployOnStartup())
	    deployApps();
 }
```

deployApps方法如下：

```java
protected void deployApps() {
	File appBase = host.getAppBaseFile();
	File configBase = host.getConfigBaseFile();
	String[] filteredAppPaths = filterAppPaths(appBase.list());
	// Deploy XML descriptors from configBase
	deployDescriptors(configBase, configBase.list());
	// Deploy WARs
	deployWARs(appBase, filteredAppPaths);
	// Deploy expanded folders
	deployDirectories(appBase, filteredAppPaths);
}
```

其中host中的一些属性解释如下：

>appBase:应用部署的目录,默认webapps
>xmlBase：通过xml形式部署应用时xml文件路径，默认null
>hostConfigBase：此属性和xmlBase功能类似,，默认null，优先级hostConfigBase>xmlBase>default路径会指向${catalina.base}/conf/engine name/host name 目录

getConfigBaseFile实际获取的就是hostConfigBase:

```java
@Override
public File getConfigBaseFile() {
	if (hostConfigBase != null) {
	    return hostConfigBase;
	}
	String path = null;
	if (getXmlBase()!=null) {
	    path = getXmlBase();
	} else {
	    StringBuilder xmlDir = new StringBuilder("conf");
	    Container parent = getParent();
	    if (parent instanceof Engine) {
	        xmlDir.append('/');
	        xmlDir.append(parent.getName());
	    }
	    xmlDir.append('/');
	    xmlDir.append(getName());
	    path = xmlDir.toString();
	}
	File file = new File(path);
	if (!file.isAbsolute())
	    file = new File(getCatalinaBase(), path);
	try {
	    file = file.getCanonicalFile();
	} catch (IOException e) {// ignore
	}
	this.hostConfigBase = file;
	return file;
}
```

另外会执行的三个方法deployDescriptors、deployWARs、deployDirectories，下面分别分析下三个方法。

##### deployDescriptors

上面自定义部署文件的方式就是调用这个方法进行的部署的。列出ConfigBaseFile下的子文件，分别创建DeployDescriptor线程任务交给host的StartStopExecutor线程池去部署人，线程中实际调用的还是HostConfig的deployDescriptor方法，代码如下：

```java
protected void deployDescriptor(ContextName cn, File contextXml) {
	// 创建app信息
	DeployedApplication deployedApp =
	        new DeployedApplication(cn.getName(), true);

	long startTime = 0;
	// Assume this is a configuration descriptor and deploy it
	if(log.isInfoEnabled()) {
	   startTime = System.currentTimeMillis();
	   log.info(sm.getString("hostConfig.deployDescriptor",
	            contextXml.getAbsolutePath()));
	}

	Context context = null;
	boolean isExternalWar = false;
	boolean isExternal = false;
	File expandedDocBase = null;

	try (FileInputStream fis = new FileInputStream(contextXml)) {
	    synchronized (digesterLock) {
	        try {
                // 通过digester解析自定义的配置文件，创建StandardContext对象
	            context = (Context) digester.parse(fis);
	        } catch (Exception e) {
	            log.error(sm.getString(
	                    "hostConfig.deployDescriptor.error",
	                    contextXml.getAbsolutePath()), e);
	        } finally {
	            if (context == null) {
	                context = new FailedContext();
	            }
	            digester.reset();
	        }
	    }
		//添加ContextConfig监听器给StandardContext
	    Class<?> clazz = Class.forName(host.getConfigClass());
	    LifecycleListener listener =
	        (LifecycleListener) clazz.newInstance();
	    context.addLifecycleListener(listener);
		//更新Context的名称和路径等，其名字和路径是ContextName中解析自定义配置文件的名字转换得到，所以说这种情况下在Context中配置path属性无效。
	    context.setConfigFile(contextXml.toURI().toURL());
	    context.setName(cn.getName());
	    context.setPath(cn.getPath());
	    context.setWebappVersion(cn.getVersion());
	    // Add the associated docBase to the redeployed list if it's a WAR
	    if (context.getDocBase() != null) {
	        File docBase = new File(context.getDocBase());
	        if (!docBase.isAbsolute()) {
	            docBase = new File(host.getAppBaseFile(), context.getDocBase());
	        }
	        // If external docBase, register .xml as redeploy first
	        if (!docBase.getCanonicalPath().startsWith(
	                host.getAppBaseFile().getAbsolutePath() + File.separator)) {
	            isExternal = true;
                //redeployResources中放入需要监听的资源信息，当发生更改，应用会重部署
                //下面的reloadResources中放入需要监听的contex中的watchedResource资源信息，当发生更改，应用会重加载
	            deployedApp.redeployResources.put(
	                    contextXml.getAbsolutePath(),
	                    Long.valueOf(contextXml.lastModified()));
	            deployedApp.redeployResources.put(docBase.getAbsolutePath(),
	                    Long.valueOf(docBase.lastModified()));
	            if (docBase.getAbsolutePath().toLowerCase(Locale.ENGLISH).endsWith(".war")) {
	                isExternalWar = true;
	            }
	        } else {
	            log.warn(sm.getString("hostConfig.deployDescriptor.localDocBaseSpecified",
	                     docBase));
	            // Ignore specified docBase
	            context.setDocBase(null);
	        }
	    }
		//通过Host的addChild方法将Context实例添加到Host中并启动
	    host.addChild(context);
	} catch (Throwable t) {
	    ExceptionUtils.handleThrowable(t);
	    log.error(sm.getString("hostConfig.deployDescriptor.error",
	                           contextXml.getAbsolutePath()), t);
	} finally {
	    // Get paths for WAR and expanded WAR in appBase

	    // default to appBase dir + name
	    expandedDocBase = new File(host.getAppBaseFile(), cn.getBaseName());
	    if (context.getDocBase() != null
	            && !context.getDocBase().toLowerCase(Locale.ENGLISH).endsWith(".war")) {
	        // first assume docBase is absolute
	        expandedDocBase = new File(context.getDocBase());
	        if (!expandedDocBase.isAbsolute()) {
	            // if docBase specified and relative, it must be relative to appBase
	            expandedDocBase = new File(host.getAppBaseFile(), context.getDocBase());
	        }
	    }

	    boolean unpackWAR = unpackWARs;
	    if (unpackWAR && context instanceof StandardContext) {
	        unpackWAR = ((StandardContext) context).getUnpackWAR();
	    }

	    // Add the eventual unpacked WAR and all the resources which will be
	    // watched inside it
	    if (isExternalWar) {
	        if (unpackWAR) {
	            deployedApp.redeployResources.put(expandedDocBase.getAbsolutePath(),
	                    Long.valueOf(expandedDocBase.lastModified()));
	            addWatchedResources(deployedApp, expandedDocBase.getAbsolutePath(), context);
	        } else {
	            addWatchedResources(deployedApp, null, context);
	        }
	    } else {
	        // Find an existing matching war and expanded folder
	        if (!isExternal) {
	            File warDocBase = new File(expandedDocBase.getAbsolutePath() + ".war");
	            if (warDocBase.exists()) {
	                deployedApp.redeployResources.put(warDocBase.getAbsolutePath(),
	                        Long.valueOf(warDocBase.lastModified()));
	            } else {
	                // Trigger a redeploy if a WAR is added
	                deployedApp.redeployResources.put(
	                        warDocBase.getAbsolutePath(),
	                        Long.valueOf(0));
	            }
	        }
	        if (unpackWAR) {
	            deployedApp.redeployResources.put(expandedDocBase.getAbsolutePath(),
	                    Long.valueOf(expandedDocBase.lastModified()));
	            addWatchedResources(deployedApp,
	                    expandedDocBase.getAbsolutePath(), context);
	        } else {
	            addWatchedResources(deployedApp, null, context);
	        }
	        if (!isExternal) {
	            // For external docBases, the context.xml will have been
	            // added above.
	            deployedApp.redeployResources.put(
	                    contextXml.getAbsolutePath(),
	                    Long.valueOf(contextXml.lastModified()));
	        }
	    }
	    // Add the global redeploy resources (which are never deleted) at
	    // the end so they don't interfere with the deletion process
	    addGlobalRedeployResources(deployedApp);
	}
	// 将此应用放入deployed的状态信息中，表示已经部署了
	if (host.findChild(context.getName()) != null) {
	    deployed.put(context.getName(), deployedApp);
	}

	if (log.isInfoEnabled()) {
	    log.info(sm.getString("hostConfig.deployDescriptor.finished",
	        contextXml.getAbsolutePath(), Long.valueOf(System.currentTimeMillis() - startTime)));
	}
}
```

总结：

>1、需要根据部署文件名做一些转换得到ContextName对象，里面包含了一些信息：baseName、name、path、version，转换规则可以参考tomcat文档
>
>2、解析部署文件构建StandardContext对象，设置一些属性，添加ContextConfig的LifecycleListener，部署逻辑主要就在这个监听器里，添加到host的chaild当中，随着context启动，解析context.xml、web.xml合并xml等，创建StandardWrapper，加入servlet的信息等
>
>3、最后要根据watchResource添加到DeployedApplication的reloadResources当中，为文件名key，value为文件时间戳；以下信息添加到redeployResources信息中：
>
>> a、${catalina.base}/conf/engine name/host name/部署文件
>>
>> b、appname.xm中的docBase的文件
>>
>> c、conf/context.xml
>
>最后deployed中put（name，DeployedApplication）信息

##### deployWARs

部署war包的形式同样创建DeployWar线程来做，主要调用deployWAR方法来部署，代码主要逻辑和上面的deployDescriptor类似，就不贴代码了，主要逻辑如下：

> 1、直接部署war包要考虑几种情况：是否解压的目录下存在context.xml、war中是否有context.xml，如果过存在则解析xml创建StandardContext，否则直接反射创建
>
> 2、解压war包之后会在META-INF下生成war-tracker文件，之后根据这个文件的时间戳和war的时间戳是否相等来决定下次部署时是否重新解压文件
>
> 3、要根据watchResource添加到DeployedApplication的reloadResources当中，为文件名key，value为文件时间戳；将以下信息添加到redeployResources信息中：
>
> > a、${catalina.base}/conf/engine name/host name/appname.xml
> >
> > b、appBase/appname目录
> >
> > c、appBase/appname.war文件
> >
> > d、appBase/appname/META-INF/context.xml
> >
> > e、conf/context.xml
>
> 4、设置copyXML，deployXML这两个属性，它们都来自Host，默认Host的copyXML为false，deployXML为true

##### deployDirectories

同样的，部署目录相应的调用deployDirectory方法，主要逻辑如下：

> 1、与deployDescriptor不同的是，如果应用/META-INF/context.xml存在，则先解析生成StandardContext，其他逻辑都是类似的
>
> 2、要根据watchResource添加到DeployedApplication的reloadResources当中，为文件名key，value为文件时间戳；将以下信息添加到redeployResources信息中：
>
> > a、${catalina.base}/conf/engine name/host name/appname.xml
> >
> > b、appBase/appname目录
> >
> > c、appBase/appname.war文件
> >
> > d、appBase/appname/META-INF/context.xml
> >
> > e、conf/context.xml
>
> 3、设置copyXML，deployXML这两个属性，它们都来自Host，默认Host的copyXML为false，deployXML为true

### 应用reload和redeploy

从上面我们知道所有应用部署之后，都会在DeployApplication中的reloadResources和redeployResources中增加监视资源，这些资源生效在哪儿？实际上tomcat启动之后，每个container都可以启动一个backgroundProcessor线程定时的做一些事情，但是默认只有StandardEngine启动时才会创建此线程，由backgroundProcessorDelay属性控制，在StandardEngine构造函数默认设置成了10，代码如下：

```java
public StandardEngine() {
	super();
	pipeline.setBasic(new StandardEngineValve());
	/* Set the jmvRoute using the system property jvmRoute */
	try {
	    setJvmRoute(System.getProperty("jvmRoute"));
	} catch(Exception ex) {
	    log.warn(sm.getString("standardEngine.jvmRouteFail"));
	}
	// By default, the engine will hold the reloading thread
	backgroundProcessorDelay = 10;
}
```

然后容器初始化启动时调用threadStart，来启动background线程，backgroundProcessorDelay 必须大于0：

```java
protected void threadStart() {
	if (thread != null)
	    return;
	if (backgroundProcessorDelay <= 0)
	    return;

	threadDone = false;
	String threadName = "ContainerBackgroundProcessor[" + toString() + "]";
	thread = new Thread(new ContainerBackgroundProcessor(), threadName);
	thread.setDaemon(true);
	thread.start();
}
```

ContainerBackgroundProcessor线程中主要调用了processChildren（container）方法，processChildren方法调用了container.backgroundProcess方法，并且递归调用对container的children执行processChildren逻辑，因此会调用到StandardHost的backgroundProcess方法中，代码如下：

```java
protected void processChildren(Container container) {
	ClassLoader originalClassLoader = null;

	try {
	if (container instanceof Context) {
	    Loader loader = ((Context) container).getLoader();
	    // Loader will be null for FailedContext instances
	    if (loader == null) {
	        return;
	    }

	    // Ensure background processing for Contexts and Wrappers
	    // is performed under the web app's class loader
	    originalClassLoader = ((Context) container).bind(false, null);
	}
	container.backgroundProcess();
	Container[] children = container.findChildren();
	for (int i = 0; i < children.length; i++) {
	    if (children[i].getBackgroundProcessorDelay() <= 0) {
	        processChildren(children[i]);
	    }
	}
	} catch (Throwable t) {
	ExceptionUtils.handleThrowable(t);
	log.error("Exception invoking periodic operation: ", t);
	} finally {
	if (container instanceof Context) {
	    ((Context) container).unbind(false, originalClassLoader);
	}
	}
}
```

backgroundProcess方法会触发所有container下的listener的Lifecycle.PERIODIC_EVENT事件，因此StandardHost的HostConfig监听器也收到了此事件并处理了，通过上面HostConfig.lifecycleEvent内容，我们知道嗲用了其check方法来做资源校验，代码如下：

```java
protected void check() {
    //首先判断StandardHost是否支持自动部署
	if (host.getAutoDeploy()) {
	    //获取已经部署的应用
	    DeployedApplication[] apps =
	        deployed.values().toArray(new DeployedApplication[0]);
	    for (int i = 0; i < apps.length; i++) {
	        if (!isServiced(apps[i].name))
	            checkResources(apps[i]);
	    }

	    // Check for old versions of applications that can now be undeployed
	    if (host.getUndeployOldVersions()) {
	        checkUndeploy();
	    }

	    // Hotdeploy applications
	    deployApps();
	}
}
```

#### redeploy

checkResources中检查需要重部署资源代码如下：

```java
String[] resources =
    app.redeployResources.keySet().toArray(new String[0]);
// Offset the current time by the resolution of File.lastModified()
long currentTimeWithResolutionOffset =
        System.currentTimeMillis() - FILE_MODIFICATION_RESOLUTION_MS;
for (int i = 0; i < resources.length; i++) {
    File resource = new File(resources[i]);
    if (log.isDebugEnabled())
        log.debug("Checking context[" + app.name +
                "] redeploy resource " + resource);
    long lastModified =
            app.redeployResources.get(resources[i]).longValue();
    if (resource.exists() || lastModified == 0) {
        // File.lastModified() has a resolution of 1s (1000ms). The last
        // modified time has to be more than 1000ms ago to ensure that
        // modifications that take place in the same second are not
        // missed. See Bug 57765.
        if (resource.lastModified() != lastModified && (!host.getAutoDeploy() ||
                resource.lastModified() < currentTimeWithResolutionOffset)) {
            //监视资源是目录，直接更新时间
            if (resource.isDirectory()) {
                // No action required for modified directory
                app.redeployResources.put(resources[i],
                        Long.valueOf(resource.lastModified()));
            //应用存在Context描述文件，并且当前变更的是WAR包时
            } else if (app.hasDescriptor &&
                    resource.getName().toLowerCase(
                            Locale.ENGLISH).endsWith(".war")) {
                // Modified WAR triggers a reload if there is an XML
                // file present
                // The only resource that should be deleted is the
                // expanded WAR (if any)
                Context context = (Context) host.findChild(app.name);
                String docBase = context.getDocBase();
                //docBase不以war结尾，则先删除解压目录，然后再重新reload，在context启动前会解压war包
                if (!docBase.toLowerCase(Locale.ENGLISH).endsWith(".war")) {
                    // This is an expanded directory
                    File docBaseFile = new File(docBase);
                    if (!docBaseFile.isAbsolute()) {
                        docBaseFile = new File(host.getAppBaseFile(),
                                docBase);
                    }
                    reload(app, docBaseFile, resource.getAbsolutePath());
                } else {
                    reload(app, null, null);
                }
                // Update times
                app.redeployResources.put(resources[i],
                        Long.valueOf(resource.lastModified()));
                app.timestamp = System.currentTimeMillis();
                boolean unpackWAR = unpackWARs;
                if (unpackWAR && context instanceof StandardContext) {
                    unpackWAR = ((StandardContext) context).getUnpackWAR();
                }
                if (unpackWAR) {
                    addWatchedResources(app, context.getDocBase(), context);
                } else {
                    addWatchedResources(app, null, context);
                }
                return;
            } else { //先卸载，再重新部署
                // Everything else triggers a redeploy
                // (just need to undeploy here, deploy will follow)
                undeploy(app);
                deleteRedeployResources(app, resources, i, false);
                return;
            }
        }
    } else {
        // There is a chance the the resource was only missing
        // temporarily eg renamed during a text editor save
        try {
            Thread.sleep(500);
        } catch (InterruptedException e1) {
            // Ignore
        }
        // Recheck the resource to see if it was really deleted
        if (resource.exists()) {
            continue;
        }
        if (lastModified == 0L) {
            continue;
        }
        // Undeploy application
        undeploy(app);
        deleteRedeployResources(app, resources, i, true);
        return;
    }
}
```

总结：

> 如果监视资源是目录，则只是更新监视资源列表的lastModified
>
> 如果应用存在Context描述文件，并且当前变更的是WAR包时，且docBase不以.war结尾（即Context指向的是WAR解压目录），则先删除解压目录，然后重新加载，否则直接重新加载，并更新监视资源信息
>
> 其他直接卸载应用，并通过deployApps重新部署应用

#### reload

checkResources中检查需要重加载资源代码如下：

```java
resources = app.reloadResources.keySet().toArray(new String[0]);
boolean update = false;
for (int i = 0; i < resources.length; i++) {
    File resource = new File(resources[i]);
    if (log.isDebugEnabled()) {
        log.debug("Checking context[" + app.name + "] reload resource " + resource);
    }
    long lastModified = app.reloadResources.get(resources[i]).longValue();
    // File.lastModified() has a resolution of 1s (1000ms). The last
    // modified time has to be more than 1000ms ago to ensure that
    // modifications that take place in the same second are not
    // missed. See Bug 57765.
    if ((resource.lastModified() != lastModified &&
            (!host.getAutoDeploy() ||
                    resource.lastModified() < currentTimeWithResolutionOffset)) ||
            update) {
        if (!update) {
            // Reload application
            reload(app, null, null);
            update = true;
        }
        // Update times. More than one file may have been updated. We
        // don't want to trigger a series of reloads.
        app.reloadResources.put(resources[i],
                Long.valueOf(resource.lastModified()));
    }
    app.timestamp = System.currentTimeMillis();
}
```

当该重加载资源文件发生变化时，不需要重新部署应用，只需调用context.reload重新加载应用（reload，即先stop，然后start），其实除此之外，应用下classes和lib下类文件的更新也会导致应用reload，原因是WebappLoader的backgroundProcess方法中做了一些校验，但是必须配置context的reloadable=true才会生效：

```java
public void backgroundProcess() {
	if (reloadable && modified()) {
	    try {
	        Thread.currentThread().setContextClassLoader
	            (WebappLoader.class.getClassLoader());
	        if (context != null) {
	            context.reload();
	        }
	    } finally {
	        if (context != null && context.getLoader() != null) {
	            Thread.currentThread().setContextClassLoader
	                (context.getLoader().getClassLoader());
	        }
	    }
	}
}
```

### 总结

tomcat的应用部署方式：

> 1、server.xml配置方式
>
> 2、自定义部署文件方式
>
> 3、直接将应用放入webapps目录，又分为三种
>
> > a、deployDescriptors也就是自定义部署文件方式
> >
> > b、deployWARs部署war包
> >
> > c、deployDirectories部署目录