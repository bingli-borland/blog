---
title: Tomcat源码分析—Bootstrap启动和停止
date: 2018-04-24 14:31:56
updated: 2018-04-24 14:31:56
tags: [tomcat, digester, java, server.xml]
categories: [tomcat]
---

### 前言

这两周比较忙，没有更新博客，有点偷懒了，不废话，本篇继续分析tomcat源码，再bootstrap那一篇Catalina.load方法中已经提到过，tomcat配置文件server.xml的解析是通过Digester，Digester源码已纳入tomcat源码中，也可以在apache的[官网](http://commons.apache.org/proper/commons-digester/)上下载到二进制文件和源码。首先我们来看一个简单的demo，然后具体分析下Digester的具体使用以及在tomcat中的使用。

### Digester解析案例

这个案例中，我们主要做的就是将xml中定义的element解析为对应的Java对象并打印一些信息。xml文件定义，employee.xml如下：

```xml
<?xml version="1.0" encoding="UTF-8"?> 
<employee firstName="Brian" lastName="May"> 
   <office> 
     <address streeName="Wellington Street" streetNumber="110"/> 
   </office> 
</employee>
```

<!--more-->

java类定义，Employee.java

```java
package com.bingli.digester.test;

import java.util.ArrayList;

public class Employee {
	private String firstName;
	private String lastName;
	private ArrayList offices = new ArrayList();

	public Employee() {
		System.out.println("Creating Employee");
	}
	public String getFirstName() {
		return firstName;
	}
	public void setFirstName(String firstName) {
		System.out.println("Setting firstName : " + firstName);
		this.firstName = firstName;
	}
	public String getLastName() {
		return lastName;
	}
	public void setLastName(String lastName) {
		System.out.println("Setting lastName : " + lastName);
		this.lastName = lastName;
	}
	public void addOffice(Office office) {
		System.out.println("Adding Office to this employee");
		offices.add(office);
	}
	public ArrayList getOffices() {
		return offices;
	}
	public void printName() {
		System.out.println("My name is " + firstName + " " + lastName);
	}
}
```

Office.java

```java
package com.bingli.digester.test;

public class Office {
	private Address address;
	private String description;
	public Office() {
		System.out.println("..Creating Office");
	}
	public String getDescription() {
		return description;
	}
	public void setDescription(String description) {
		System.out.println("..Setting office description : " + description);
		this.description = description;
	}
	public Address getAddress() {
		return address;
	}
	public void setAddress(Address address) {
		System.out.println("..Setting office address : " + address);
		this.address = address;
	}
}
```

Address.java

```java
package com.bingli.digester.test;

public class Address {
	private String streetName;
	private String streetNumber;
	public Address() {
		System.out.println("....Creating Address");
	}
	public String getStreetName() {
		return streetName;
	}
	public void setStreetName(String streetName) {
		System.out.println("....Setting streetName : " + streetName);
		this.streetName = streetName;
	}
	public String getStreetNumber() {
		return streetNumber;
	}
	public void setStreetNumber(String streetNumber) {
		System.out.println("....Setting streetNumber : " + streetNumber);
		this.streetNumber = streetNumber;
	}
	public String toString() {
		return "...." + streetNumber + " " + streetName;
	}
}

```

Test01.java

```java
package com.bingli.digester.test;

import java.io.File;
import org.apache.tomcat.util.digester.Digester;

public class Test01 {
	public static void main(String[] args) {
        // 配置需要解析的xml文件
        String path = System.getProperty("user.dir") + File.separator + "src";
        File file = new File(path, "employee.xml");         
        // 解析的主类Digester
        Digester digester = new Digester();		
        // 增加匹配模式
        digester.addObjectCreate("employee", "com.bingli.digester.test.Employee");
        digester.addSetProperties("employee");
        digester.addCallMethod("employee", "printName");

        try {
            Employee employee = (Employee) digester.parse(file);
            System.out.println("First name : " + employee.getFirstName());
            System.out.println("Last name : " + employee.getLastName());
        } catch (Exception e) {
            e.printStackTrace();
        }
	}
}
```

Test01.java执行结果：

```xml
Creating Employee
Setting firstName : Brian
Setting lastName : May
My name is Brian May
First name : Brian
Last name : May
```

根据结果，分析解析过程如下：

1、digester通过Employee构造函数创建Employee对象

2、调用set方法设置firstName和lastName属性

3、digester调用employee对象的printName方法

### Digester 基本api介绍

在上面的例子中，org.apache.tomcat.util.digester.Digester类是Digester库的主类，该类可用于解析xml文件，对与xml文档中的每个元素，Digester对象都会检查是否要做事先预定义的事件，在进行xml解析之前，开发人员需要设计匹配模式。employee.xml文件中根元素是employee，employee元素的有一个模式employee。office是employee的子元素，因此，office的模式是employee/office。以此类推，address元素的模式是employee/office/address。

#### 对象创建

若想要digester根据找到的模式创建相应的对象，则可以调用addObjectCreate方法。该方法有四个重载版本，比较有用的是下面两个：

***public void addObjectCreate(String pattern, Class clazz)***

根据类的Class对象来创建，eg：

```java
digester.addObjectCreate("employee", Employee.class);
```

***public void addObjectCreate(String pattern, String className)***

根据类的完成类名创建，eg：

```java
digester.addObjectCreate("employee", "com.bingli.digester.test.Employee");
```

***public void addObjectCreate(String pattern, String className, String attributeName)***

根据element的属性的值创建对象，当找不到属性，这使用默认的类名，eg:

```xml
<?xml version="1.0" encoding="UTF-8"?> 
<employee firstName="Brian" lastName="May" className="com.bingli.digester.test.Employee"> 
</employee>
```

```java
digester.addObjectCreate("employee", "com.bingli.digester.test.Employee", "className");
```

***public void addObjectCreate(String pattern, String attributeName, Class clazz)***

 根据element的属性的值创建对象，当找不到属性，这使用默认的类的Class对象创建。
```xml
<?xml version="1.0" encoding="UTF-8"?> 
<employee firstName="Brian" lastName="May" className="com.bingli.digester.test.Employee"> 
</employee>
```

```java
digester.addObjectCreate("employee", "className", Employee.class);
```


#### 设置属性

使用该方法可以为创建的对象设置属性。其中的一个重载方法的签名是：

***public void addSetProperties(String pattern)***

使用时，传入一个模式字符串，eg：

```java
digester.addObjectCreate("employee", "com.bingli.digester.test.Employee");
digester.addSetProperties("employee");
```

上面的digester对象有两个rule，创建对象和设置属性，都是通过“employee”模式触发的。rule按照其

添加到digester中的顺序执行。Digester对象会首先创建com.bingli.digester.test.Employee对象，然后调用setFirstName和setLastName方法设置属性。

#### 调用对象方法

Digester类允许通过添加一个rule的方式来调用栈顶对象的方法。该方法签名如下：

***public void addCallMethod (String pattern, String methodName)***

```java
digester.addCallMethod("employee", "printName");
```

#### 构建对象之间的关系

Digester对象中包含有一个内部栈，用于临时存储创建的对象。当使用addObjectCreate方法创建一个对

象时，生成的对象会存储在这个栈中。addSetNext方法用于创建栈中两个对象之间的关系，实际上，这两个对象是xml文件中两个具有父子关系的标签所对应的对象。方法签名如下：

***public void addSetNext(String pattern, String methodName)***

其中，参数pattern是子元素对应的模式，参数methodName是父元素添加子元素时使用的方法名。考

虑到Digester创建对象时会先创建父元素对应的对象，相比于子元素对象，父元素对象会更靠近栈底，eg：

```java
digester.addObjectCreate("employee", "com.bingli.digester.test.Employee");
digester.addSetProperties("employee");    
digester.addObjectCreate("employee/office", "com.bingli.digester.test.Office");
digester.addSetProperties("employee/office");
digester.addSetNext("employee/office", "addOffice");
```

假如office下还有子元素，并增加了这样的模式，setAddress和addOffice谁先执行？

```java
digester.addObjectCreate("employee/office/address", "com.bingli.digester.test.Address");
digester.addSetProperties("employee/office/address");
digester.addSetNext("employee/office/address", "setAddress");
```

答案是**addOffice的操作会在setAddress操作完成之后进行**

#### 验证xml文档

Digester对象解析的xml文档的有效性可通过schema进行验证，然后将结果记录与Digester对象的

validating属性中，该属性默认为false。setValidating方法用于设置是否要对xml文件进行验证，方法签名如下：

***public void setValidating(boolean validating)***

#### 模式规则Rule

Rule类中包含了一些方法，其中最重要的是begin和end方法。当Digester对象遇到xml文档的开始标签时，会调用匹配规则的begin方法；当遇到结束标签时，会调用end方法。Rule类的begin和end方法的签名如下：

***public void begin(org.xml.sax.Attributes attributes) throws java.lang.Exception***

***public void end() throws java.lang.Exception***

来看看SetNextRule.end方法，实际就是通过IntrospectionUtils这个工具反射调用parent的方法将child设置进去：

```java
public void end(String namespace, String name) throws Exception {
    // Identify the objects to be used
    Object child = digester.peek(0);
    Object parent = digester.peek(1);
    if (digester.log.isDebugEnabled()) {
        if (parent == null) {
            digester.log.debug("[SetNextRule]{" + digester.match +
                               "} Call [NULL PARENT]." +
                               methodName + "(" + child + ")");
        } else {
            digester.log.debug("[SetNextRule]{" + digester.match +
                               "} Call " + parent.getClass().getName() + "." +
                               methodName + "(" + child + ")");
        }
    }

    // Call the specified method
    IntrospectionUtils.callMethod1(parent, methodName,
                                   child, paramType, digester.getClassLoader());

}
```

Digester对象是如何完成这些工作的呢？当调用digester对象的addObjectCreate，addCallMethod，addSetNext或其他方法时，实际上是调用digester的addRule方法，该方法会将一个rule对象和它所匹配的模式添加到digester对象中。addRule方法签名如下：

***public void addRule(String pattern, Rule rule)***

Digester类的addRule方法的实现如下：

```java
public void addRule(String pattern, Rule rule) { 
   rule.setDigester(this); 
   getRules().add(pattern, rule); 
}
```

继续查看Digester类的addObjectCreate方法的重载实现，实际就是调用了上面的addRule方法如下：

```java
public void addObjectCreate(String pattern, String className) { 
   addRule(pattern, new ObjectCreateRule(className)); 
} 
```

我们查看Digester的其他方法，都会找到对应的xxxRule。

#### 模式规则集合RuleSet

digester对象中添加rule还可以调用addRuleSet方法，方法签名如下：

***public void addRuleSet(RuleSet ruleSet)***

RuleSet类表示了rule对象的集合。创建了digester对象后，可以创建一个RuleSet对象，然后将RuleSet对象传给digester的addRuleSet方法。该接口定义了两个方法addRuleInstance和getNamespaceURI，方法签名如下：

***public void addRuleInstance(Digester digester)*** 添加rule集合到digester对象中

***public String getNamespaceURI()***  返回命名空间uri，uri会匹配到RuleSet中所有的rule对象

RuleSetBase类实现了RuleSet接口，RuleSetBase是一个虚类，提供了getNamespaceURI方法的实现，

使用者只需要提供addRuleInstance方法的实现即可。eg:

```java
package com.bingli.digester.test;

import org.apache.tomcat.util.digester.Digester;
import org.apache.tomcat.util.digester.RuleSetBase;

public class EmployeeRuleSet extends RuleSetBase {
	public void addRuleInstances(Digester digester) {
		// add rules
		digester.addObjectCreate("employee", "com.bingli.digester.test.Employee");
		digester.addSetProperties("employee");
		digester.addObjectCreate("employee/office", "com.bingli.digester.test.Office");
		digester.addSetProperties("employee/office");
		digester.addSetNext("employee/office", "addOffice");
		digester.addObjectCreate("employee/office/address", "com.bingli.digester.test.Address");
		digester.addSetProperties("employee/office/address");
		digester.addSetNext("employee/office/address", "setAddress");
	}
}

```

```java
package com.bingli.digester.test;

import java.io.File;
import java.util.ArrayList;
import java.util.Iterator;
import org.apache.tomcat.util.digester.Digester;

public class Test02 {

	public static void main(String[] args) {
		String path = System.getProperty("user.dir") + File.separator + "src";
		File file = new File(path, "employee.xml");
		Digester digester = new Digester();
		digester.addRuleSet(new EmployeeRuleSet());
		try {
			Employee employee = (Employee) digester.parse(file);
		} catch (Exception e) {
			e.printStackTrace();
		}
	}
}
```

### Tomcat中使用Digester

tomcat中部分Rule的实现：

```java
ObjectCreateRule
CallMethodRule
SetPropertiesRule
SetNextRule
```

tomcat中定义的RuleSet：

```java
ContextRuleSet --解析server.xml中的Server/Service/Engine/Host/Context元素、context.xml
EngineRuleSet  --解析Server/Service/Engine元素
HostRuleSet    --解析Server/Service/Engine/Host元素
MemoryRuleSet  --解析tomcat-users.xml
NamingRuleSet  --解析Server/GlobalNamingResources和Server/Service/Engine/Host/Context下Resource等
RealmRuleSet   --解析Context、Engine、Host下的Realm元素
TldRuleSet     --解析.tld文件 
WebRuleSet     --解析web.xml、web-fragment.xml
```

#### server.xml解析

Catalina.load中解析server.xml代码如下：

```java
public void load() {
    	// 省略部分代码......
        // Create and execute our Digester
        Digester digester = createStartDigester();
        InputSource inputSource = null;
        InputStream inputStream = null;
        File file = null;
        try {
            try {
                file = configFile();
                inputStream = new FileInputStream(file);
                inputSource = new InputSource(file.toURI().toURL().toString());
            } catch (Exception e) {
                if (log.isDebugEnabled()) {
                    log.debug(sm.getString("catalina.configFail", file), e);
                }
            }
            // 省略部分代码......
            try {
                inputSource.setByteStream(inputStream);
                digester.push(this);
                digester.parse(inputSource);
            } catch (SAXParseException spe) {
                log.warn("Catalina.start using " + getConfigFile() + ": " +
                        spe.getMessage());
                return;
            } catch (Exception e) {
                log.warn("Catalina.start using " + getConfigFile() + ": " , e);
                return;
            }
        } finally {
            if (inputStream != null) {
                try {
                    inputStream.close();
                } catch (IOException e) {
                    // Ignore
                }
            }
        }
        getServer().setCatalina(this);
        // 省略部分代码......
    }

```

Digester对象创建，前面所说的Rule和RuleSet在此处都有使用，具体每行代码的作用可以对比上面的案例：

```java
protected Digester createStartDigester() {
    long t1=System.currentTimeMillis();
    // Initialize the digester
    Digester digester = new Digester();
    digester.setValidating(false);
    digester.setRulesValidation(true);
    HashMap<Class<?>, List<String>> fakeAttributes =
        new HashMap<Class<?>, List<String>>();
    ArrayList<String> attrs = new ArrayList<String>();
    attrs.add("className");
    fakeAttributes.put(Object.class, attrs);
    digester.setFakeAttributes(fakeAttributes);
    digester.setUseContextClassLoader(true);

    // Configure the actions we will be using
    digester.addObjectCreate("Server",
                             "org.apache.catalina.core.StandardServer",
                             "className");
    digester.addSetProperties("Server");
    digester.addSetNext("Server",
                        "setServer",
                        "org.apache.catalina.Server");

    digester.addObjectCreate("Server/GlobalNamingResources",
                             "org.apache.catalina.deploy.NamingResources");
    digester.addSetProperties("Server/GlobalNamingResources");
    digester.addSetNext("Server/GlobalNamingResources",
                        "setGlobalNamingResources",
                        "org.apache.catalina.deploy.NamingResources");

    digester.addObjectCreate("Server/Listener",
                             null, // MUST be specified in the element
                             "className");
    digester.addSetProperties("Server/Listener");
    digester.addSetNext("Server/Listener",
                        "addLifecycleListener",
                        "org.apache.catalina.LifecycleListener");

    digester.addObjectCreate("Server/Service",
                             "org.apache.catalina.core.StandardService",
                             "className");
    digester.addSetProperties("Server/Service");
    digester.addSetNext("Server/Service",
                        "addService",
                        "org.apache.catalina.Service");

    digester.addObjectCreate("Server/Service/Listener",
                             null, // MUST be specified in the element
                             "className");
    digester.addSetProperties("Server/Service/Listener");
    digester.addSetNext("Server/Service/Listener",
                        "addLifecycleListener",
                        "org.apache.catalina.LifecycleListener");

    //Executor
    digester.addObjectCreate("Server/Service/Executor",
                             "org.apache.catalina.core.StandardThreadExecutor",
                             "className");
    digester.addSetProperties("Server/Service/Executor");

    digester.addSetNext("Server/Service/Executor",
                        "addExecutor",
                        "org.apache.catalina.Executor");


    digester.addRule("Server/Service/Connector",
                     new ConnectorCreateRule());
    digester.addRule("Server/Service/Connector",
                     new SetAllPropertiesRule(new String[]{"executor"}));
    digester.addSetNext("Server/Service/Connector",
                        "addConnector",
                        "org.apache.catalina.connector.Connector");


    digester.addObjectCreate("Server/Service/Connector/Listener",
                             null, // MUST be specified in the element
                             "className");
    digester.addSetProperties("Server/Service/Connector/Listener");
    digester.addSetNext("Server/Service/Connector/Listener",
                        "addLifecycleListener",
                        "org.apache.catalina.LifecycleListener");

    // Add RuleSets for nested elements
    digester.addRuleSet(new NamingRuleSet("Server/GlobalNamingResources/"));
    digester.addRuleSet(new EngineRuleSet("Server/Service/"));
    digester.addRuleSet(new HostRuleSet("Server/Service/Engine/"));
    digester.addRuleSet(new ContextRuleSet("Server/Service/Engine/Host/"));
    addClusterRuleSet(digester, "Server/Service/Engine/Host/Cluster/");
    digester.addRuleSet(new NamingRuleSet("Server/Service/Engine/Host/Context/"));

    // When the 'engine' is found, set the parentClassLoader.
    digester.addRule("Server/Service/Engine",
                     new SetParentClassLoaderRule(parentClassLoader));
    addClusterRuleSet(digester, "Server/Service/Engine/Cluster/");

    long t2=System.currentTimeMillis();
    if (log.isDebugEnabled()) {
        log.debug("Digester for server.xml created " + ( t2-t1 ));
    }
    return (digester);
}
```

此处我们需要注意一个问题，由于Server是根元素，而且Catalina中调用digester.parse()解析出的对象并没有被Catalina中的server直接的引用（实际上parse出来的是Catalina对象），究竟是在什么地方设置进来的呢？原因在这儿：

```java
// createStartDigester方法中
digester.addObjectCreate("Server", "org.apache.catalina.core.StandardServer", "className");
digester.addSetProperties("Server");
digester.addSetNext("Server", "setServer", "org.apache.catalina.Server");

// load方法中
digester.push(this);
digester.parse(inputSource);
```

addSetNext设置对象关系，Server并没有父对象，但是在parse之前通过digester.push()将Catalina对象压至栈底，因为还未开始解析，所以Catalina才是实际上的根元素，因此解析完在end方法中将Canalina作为父对象，并反射调用setServer方法将server设置给Catalina的server引用。

#### context.xml和web.xml解析

context.xml和web.xml解析主要是部署过程中解析，主要是在ContextConfig.init方法中，ContextConfig实现了LifecycleListener接口，并添加给了StandardContext，因此应用部署的时候会做解析操作。

```java
protected void init() {
    // Called from StandardContext.init()
    Digester contextDigester = createContextDigester();
    contextDigester.getParser();
    if (log.isDebugEnabled())
    	log.debug(sm.getString("contextConfig.init"));
    context.setConfigured(false);
    ok = true;
    // 解析context.xml
    contextConfig(contextDigester);
    // 解析web.xml以及web-fragment.xml
    createWebXmlDigester(context.getXmlNamespaceAware(), context.getXmlValidation());
}
```

对于tomcat配置解析就写这么多，Digester还有一些用法可以去官网看api文件和使用手册。



