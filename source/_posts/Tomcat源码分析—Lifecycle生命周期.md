---
title: Tomcat源码分析—Lifecycle生命周期
date: 2018-04-08 14:05:56
tags: [tomcat, lifecycle, java, server]
categories: [tomcat]
---
### 前言

在tomcat中有很多组件，如果需要一个一个启动，不仅麻烦，而且容易遗漏。使用Lifecycle管理启动、停止组件就可以解决这个问题。tomcat核心组件又包含和被包含的关系，也就是父组件和子组件的关系，子组件由父组件启动，这样只要启动根组件即可把其他组件都启动起来。例如Server包含service，service包含container和connector。Lifecycle中主要类和接口以及结构图如下：

1. Lifecycle接口（要使用生命周期控制的类都会继承该类）
2. LifecycleListener接口（监听器都会继承该类）
3. LifecycleSupport类（用来对监听器进行管理）
4. LifecycleEvent类（该类是一个辅助类，用来作为参数类型）
5. LifecycleException类（异常类）

<!--more-->

![](Tomcat源码分析—Lifecycle生命周期\lifecycle.jpg)

### Lifecycle状态变化

Lifecycle接口时组件生命周期方法的通用接口，tomcat组件可以实现这个接口以提供一致的机制
启动和停止组件。组件状态转换图：

```java
             start()
   -----------------------------
   |                           |
   | init()                    |
  NEW -»-- INITIALIZING        |
  | |           |              |     ------------------«-----------------------
  | |           |auto          |     |                                        |
  | |          \|/    start() \|/   \|/     auto          auto         stop() |
  | |      INITIALIZED --»-- STARTING_PREP --»- STARTING --»- STARTED --»---  |
  | |         |                                                            |  |
  | |destroy()|                                                            |  |
  | --»-----«--    ------------------------«--------------------------------  ^
  |     |          |                                                          |
  |     |         \|/          auto                 auto              start() |
  |     |     STOPPING_PREP ----»---- STOPPING ------»----- STOPPED -----»-----
  |    \|/                               ^                     |  ^
  |     |               stop()           |                     |  |
  |     |       --------------------------                     |  |
  |     |       |                                              |  |
  |     |       |    destroy()                       destroy() |  |
  |     |    FAILED ----»------ DESTROYING ---«-----------------  |
  |     |                        ^     |                          |
  |     |     destroy()          |     |auto                      |
  |     --------»-----------------    \|/                         |
  |                                 DESTROYED                     |
  |                                                               |
  |                            stop()                             |
  ---»------------------------------»------------------------------
```

需要注意以下几点：

```
1.任何状态都能转换为FAILED状态
2.当组件处于STARTING_PREP, STARTING or STARTED状态时，调用start方法无效
3.当组件处于NEW状态时调用start（）方法将导致在进入start（）方法后立即调用init（）方法
4.当组件处于STOPPING_PREP, STOPPING or STOPPED状态时，调用stop方法无效
5.当组件处于NEW状态时可以调用stop（）方法会将组件状态转换为STOPPED，通常会遇到组件未能启动并且没有启动其所有子组件，组件停止时，它会尝试停止所有的子组件，即使它没有启动
6.状态更改期间触发的LifecycleEvent时在触发状态转换的方法中定义的，如果尝试的转换无效，则不会触发LifecycleEvent
7.尝试其他的状态转换（已经定义的状态转换之外）将会抛出LifecycleException
```

代码中的体现：

![](Tomcat源码分析—Lifecycle生命周期\start.jpg)

![](Tomcat源码分析—Lifecycle生命周期\stop.jpg)

Lifestyle中主要定义了生命周期事件类型和生命周期接口方法：

```java
public interface Lifecycle {
	// 事件类型
    public static final String BEFORE_INIT_EVENT = "before_init";
    public static final String AFTER_INIT_EVENT = "after_init";
    public static final String START_EVENT = "start";
    public static final String BEFORE_START_EVENT = "before_start";
    public static final String AFTER_START_EVENT = "after_start";
    public static final String STOP_EVENT = "stop";
    public static final String BEFORE_STOP_EVENT = "before_stop";
    public static final String AFTER_STOP_EVENT = "after_stop";
    public static final String AFTER_DESTROY_EVENT = "after_destroy";
    public static final String BEFORE_DESTROY_EVENT = "before_destroy";
    public static final String PERIODIC_EVENT = "periodic";
    public static final String CONFIGURE_START_EVENT = "configure_start";
    public static final String CONFIGURE_STOP_EVENT = "configure_stop";
	// 事件监听器
    public void addLifecycleListener(LifecycleListener listener);
    public LifecycleListener[] findLifecycleListeners();
    public void removeLifecycleListener(LifecycleListener listener);
	// 生命周期管理
    public void init() throws LifecycleException;
    public void start() throws LifecycleException;
    public void stop() throws LifecycleException;
    public void destroy() throws LifecycleException;
    public LifecycleState getState();
    public String getStateName();
}
```

LifecycleState定义了组件状态以及获取此状态对应的事件LifecycleEvent：

```java
public enum LifecycleState {
    // 组件状态类型，大部分有对应的事件
    NEW(false, null),
    INITIALIZING(false, Lifecycle.BEFORE_INIT_EVENT),
    INITIALIZED(false, Lifecycle.AFTER_INIT_EVENT),
    STARTING_PREP(false, Lifecycle.BEFORE_START_EVENT),
    STARTING(true, Lifecycle.START_EVENT),
    STARTED(true, Lifecycle.AFTER_START_EVENT),
    STOPPING_PREP(true, Lifecycle.BEFORE_STOP_EVENT),
    STOPPING(false, Lifecycle.STOP_EVENT),
    STOPPED(false, Lifecycle.AFTER_STOP_EVENT),
    DESTROYING(false, Lifecycle.BEFORE_DESTROY_EVENT),
    DESTROYED(false, Lifecycle.AFTER_DESTROY_EVENT),
    FAILED(false, null),
	// 当前状态下组件是否可用
    private final boolean available;
    private final String lifecycleEvent;

    private LifecycleState(boolean available, String lifecycleEvent) {
        this.available = available;
        this.lifecycleEvent = lifecycleEvent;
    }
    public boolean isAvailable() {
        return available;
    }
    public String getLifecycleEvent() {
        return lifecycleEvent;
    }
}
```



### Lifecycle事件监听机制

上面存在很多状态转换，如果想在某个状态转换事件发生前后做一些上面处理，tomcat采用了事件监听器模式来实现这个功能，tomcat的事件监听器组成部分：

1.事件对象——LifestyleEvent，继承自java.util.EvenObject

```java
public final class LifecycleEvent extends EventObject {
    private static final long serialVersionUID = 1L;
    public LifecycleEvent(Lifecycle lifecycle, String type, Object data) {
        super(lifecycle);
        this.type = type;
        this.data = data;
    }
    private Object data = null;
    private String type = null;
    public Object getData() {
        return (this.data);
    }
    public Lifecycle getLifecycle() {
        return (Lifecycle) getSource();
    }
    public String getType() {
        return (this.type);
    }
}
```



2.事件源——server、service、connector、container

3.事件监听器——LifecycleListener接口，定义了lifecycleEvent（LifestyleEvent）方法来处理事件

```java
public interface LifecycleListener {
    public void lifecycleEvent(LifecycleEvent event);
}
```



4.辅助类——LifecycleSupport维护了监听器数组，并提供注册、解注册、触发监听器等方法

```java
public final class LifecycleSupport {

    public LifecycleSupport(Lifecycle lifecycle) {
        super();
        this.lifecycle = lifecycle;
    }
	// 事件源，引用了一个实现Lifecycle的组件
    private Lifecycle lifecycle = null;
	// 监听器数组
    private LifecycleListener listeners[] = new LifecycleListener[0];
    
    private final Object listenersLock = new Object(); // Lock object for changes to listeners
	
    public void addLifecycleListener(LifecycleListener listener) {
      synchronized (listenersLock) {
          LifecycleListener results[] =
            new LifecycleListener[listeners.length + 1];
          for (int i = 0; i < listeners.length; i++)
              results[i] = listeners[i];
          results[listeners.length] = listener;
          listeners = results;
      }
    }

    public LifecycleListener[] findLifecycleListeners() {
        return listeners;
    }
	// 触发事件
    public void fireLifecycleEvent(String type, Object data) {
        LifecycleEvent event = new LifecycleEvent(lifecycle, type, data);
        LifecycleListener interested[] = listeners;
        for (int i = 0; i < interested.length; i++)
            interested[i].lifecycleEvent(event);
    }

    public void removeLifecycleListener(LifecycleListener listener) {
        synchronized (listenersLock) {
            int n = -1;
            for (int i = 0; i < listeners.length; i++) {
                if (listeners[i] == listener) {
                    n = i;
                    break;
                }
            }
            if (n < 0)
                return;
            LifecycleListener results[] =
              new LifecycleListener[listeners.length - 1];
            int j = 0;
            for (int i = 0; i < listeners.length; i++) {
                if (i != n)
                    results[j++] = listeners[i];
            }
            listeners = results;
        }
    }
}
```



使用监听器生效整个流程，自定义XXXLifecycleListener，实现LifecycleListener接口，重写lifecycleEvent方法，调用LifecycleSupport的addLifecycleListener方法注册即可。但是在tomcat中，我们很少直接调用LifecycleSupport类来注册监听器，这是为什么？

tomcat为了方便使用LifecycleSupport，又抽象出来了一个LifecycleBase抽象类，实现了Lifecycle接口，我们来看下这个类的结构：

```java
public abstract class LifecycleBase implements Lifecycle {
    private static Log log = LogFactory.getLog(LifecycleBase.class);
    private static StringManager sm =
        StringManager.getManager("org.apache.catalina.util");
    // 监听器辅助类
    private LifecycleSupport lifecycle = new LifecycleSupport(this);
    // 默认组件的状态
    private volatile LifecycleState state = LifecycleState.NEW;

    // 实现了监听器的注册、解注册、查找、方法，这些都在Lifecycle接口中定义
    @Override
    public void addLifecycleListener(LifecycleListener listener) {
        lifecycle.addLifecycleListener(listener);
    }
    @Override
    public LifecycleListener[] findLifecycleListeners() {
        return lifecycle.findLifecycleListeners();
    }
    @Override
    public void removeLifecycleListener(LifecycleListener listener) {
        lifecycle.removeLifecycleListener(listener);
    }
    // 定义了触发事件的方法，实际上就是调用辅助类来触发
    protected void fireLifecycleEvent(String type, Object data) {
        lifecycle.fireLifecycleEvent(type, data);
    }

    // 实现了生命周期中主要的init、start、stop、destroy方法，而且都定义了各自的xxxInternal抽象方法
    // 这里实际上就是使用了模板模式，方便各个组件自己扩展，同时又不破坏原有的状态转换顺序
    @Override
    public final synchronized void init() throws LifecycleException {
        if (!state.equals(LifecycleState.NEW)) {
            invalidTransition(Lifecycle.BEFORE_INIT_EVENT);
        }
        try {
            setStateInternal(LifecycleState.INITIALIZING, null, false);
            initInternal();
            setStateInternal(LifecycleState.INITIALIZED, null, false);
        } catch (Throwable t) {
            ExceptionUtils.handleThrowable(t);
            setStateInternal(LifecycleState.FAILED, null, false);
            throw new LifecycleException(
                    sm.getString("lifecycleBase.initFail",toString()), t);
        }
    }
    protected abstract void initInternal() throws LifecycleException;

    @Override
    public final synchronized void start() throws LifecycleException {

        if (LifecycleState.STARTING_PREP.equals(state) || LifecycleState.STARTING.equals(state) ||
                LifecycleState.STARTED.equals(state)) {
            if (log.isDebugEnabled()) {
                Exception e = new LifecycleException();
                log.debug(sm.getString("lifecycleBase.alreadyStarted", toString()), e);
            } else if (log.isInfoEnabled()) {
                log.info(sm.getString("lifecycleBase.alreadyStarted", toString()));
            }
            return;
        }
        if (state.equals(LifecycleState.NEW)) {
            init();
        } else if (state.equals(LifecycleState.FAILED)) {
            stop();
        } else if (!state.equals(LifecycleState.INITIALIZED) &&
                !state.equals(LifecycleState.STOPPED)) {
            invalidTransition(Lifecycle.BEFORE_START_EVENT);
        }
        try {
            setStateInternal(LifecycleState.STARTING_PREP, null, false);
            startInternal();
            if (state.equals(LifecycleState.FAILED)) {
                // This is a 'controlled' failure. The component put itself into the
                // FAILED state so call stop() to complete the clean-up.
                stop();
            } else if (!state.equals(LifecycleState.STARTING)) {
                // Shouldn't be necessary but acts as a check that sub-classes are
                // doing what they are supposed to.
                invalidTransition(Lifecycle.AFTER_START_EVENT);
            } else {
                setStateInternal(LifecycleState.STARTED, null, false);
            }
        } catch (Throwable t) {
            // This is an 'uncontrolled' failure so put the component into the
            // FAILED state and throw an exception.
            ExceptionUtils.handleThrowable(t);
            setStateInternal(LifecycleState.FAILED, null, false);
            throw new LifecycleException(sm.getString("lifecycleBase.startFail", toString()), t);
        }
    }
    protected abstract void startInternal() throws LifecycleException;

    @Override
    public final synchronized void stop() throws LifecycleException {
        if (LifecycleState.STOPPING_PREP.equals(state) || LifecycleState.STOPPING.equals(state) ||
                LifecycleState.STOPPED.equals(state)) {

            if (log.isDebugEnabled()) {
                Exception e = new LifecycleException();
                log.debug(sm.getString("lifecycleBase.alreadyStopped", toString()), e);
            } else if (log.isInfoEnabled()) {
                log.info(sm.getString("lifecycleBase.alreadyStopped", toString()));
            }

            return;
        }

        if (state.equals(LifecycleState.NEW)) {
            state = LifecycleState.STOPPED;
            return;
        }
        if (!state.equals(LifecycleState.STARTED) && !state.equals(LifecycleState.FAILED)) {
            invalidTransition(Lifecycle.BEFORE_STOP_EVENT);
        }
        try {
            if (state.equals(LifecycleState.FAILED)) {
                // Don't transition to STOPPING_PREP as that would briefly mark the
                // component as available but do ensure the BEFORE_STOP_EVENT is
                // fired
                fireLifecycleEvent(BEFORE_STOP_EVENT, null);
            } else {
                setStateInternal(LifecycleState.STOPPING_PREP, null, false);
            }

            stopInternal();

            // Shouldn't be necessary but acts as a check that sub-classes are
            // doing what they are supposed to.
            if (!state.equals(LifecycleState.STOPPING) && !state.equals(LifecycleState.FAILED)) {
                invalidTransition(Lifecycle.AFTER_STOP_EVENT);
            }

            setStateInternal(LifecycleState.STOPPED, null, false);
        } catch (Throwable t) {
            ExceptionUtils.handleThrowable(t);
            setStateInternal(LifecycleState.FAILED, null, false);
            throw new LifecycleException(sm.getString("lifecycleBase.stopFail",toString()), t);
        } finally {
            if (this instanceof Lifecycle.SingleUse) {
                // Complete stop process first
                setStateInternal(LifecycleState.STOPPED, null, false);
                destroy();
            }
        }
    }
    protected abstract void stopInternal() throws LifecycleException;


    @Override
    public final synchronized void destroy() throws LifecycleException {
        if (LifecycleState.FAILED.equals(state)) {
            try {
                // Triggers clean-up
                stop();
            } catch (LifecycleException e) {
                // Just log. Still want to destroy.
                log.warn(sm.getString(
                        "lifecycleBase.destroyStopFail", toString()), e);
            }
        }

        if (LifecycleState.DESTROYING.equals(state) ||
                LifecycleState.DESTROYED.equals(state)) {

            if (log.isDebugEnabled()) {
                Exception e = new LifecycleException();
                log.debug(sm.getString("lifecycleBase.alreadyDestroyed", toString()), e);
            } else if (log.isInfoEnabled() && !(this instanceof Lifecycle.SingleUse)) {
                // Rather than have every component that might need to call
                // destroy() check for SingleUse, don't log an info message if
                // multiple calls are made to destroy()
                log.info(sm.getString("lifecycleBase.alreadyDestroyed", toString()));
            }

            return;
        }

        if (!state.equals(LifecycleState.STOPPED) &&
                !state.equals(LifecycleState.FAILED) &&
                !state.equals(LifecycleState.NEW) &&
                !state.equals(LifecycleState.INITIALIZED)) {
            invalidTransition(Lifecycle.BEFORE_DESTROY_EVENT);
        }

        try {
            setStateInternal(LifecycleState.DESTROYING, null, false);
            destroyInternal();
            setStateInternal(LifecycleState.DESTROYED, null, false);
        } catch (Throwable t) {
            ExceptionUtils.handleThrowable(t);
            setStateInternal(LifecycleState.FAILED, null, false);
            throw new LifecycleException(
                    sm.getString("lifecycleBase.destroyFail",toString()), t);
        }
    }


    protected abstract void destroyInternal() throws LifecycleException;

    @Override
    public LifecycleState getState() {
        return state;
    }

    @Override
    public String getStateName() {
        return getState().toString();
    }

    protected synchronized void setState(LifecycleState state)
            throws LifecycleException {
        setStateInternal(state, null, true);
    }

    protected synchronized void setState(LifecycleState state, Object data)
            throws LifecycleException {
        setStateInternal(state, data, true);
    }

    private synchronized void setStateInternal(LifecycleState state,
            Object data, boolean check) throws LifecycleException {

        if (log.isDebugEnabled()) {
            log.debug(sm.getString("lifecycleBase.setState", this, state));
        }

        if (check) {
            // Must have been triggered by one of the abstract methods (assume
            // code in this class is correct)
            // null is never a valid state
            if (state == null) {
                invalidTransition("null");
                // Unreachable code - here to stop eclipse complaining about
                // a possible NPE further down the method
                return;
            }

            // Any method can transition to failed
            // startInternal() permits STARTING_PREP to STARTING
            // stopInternal() permits STOPPING_PREP to STOPPING and FAILED to
            // STOPPING
            if (!(state == LifecycleState.FAILED ||
                    (this.state == LifecycleState.STARTING_PREP &&
                            state == LifecycleState.STARTING) ||
                    (this.state == LifecycleState.STOPPING_PREP &&
                            state == LifecycleState.STOPPING) ||
                    (this.state == LifecycleState.FAILED &&
                            state == LifecycleState.STOPPING))) {
                // No other transition permitted
                invalidTransition(state.name());
            }
        }

        this.state = state;
        String lifecycleEvent = state.getLifecycleEvent();
        if (lifecycleEvent != null) {
            fireLifecycleEvent(lifecycleEvent, data);
        }
    }

    private void invalidTransition(String type) throws LifecycleException {
        String msg = sm.getString("lifecycleBase.invalidTransition", type,
                toString(), state);
        throw new LifecycleException(msg);
    }
}
```

除此之外，我们来看看，tomcat中究竟有多少组件实现了Lifecycle接口：

![](Tomcat源码分析—Lifecycle生命周期\lifecycle-arch.jpg)

1.LifecycleMBeanBase抽象类继承了LifecycleBase类，实现了javax.management.MBeanRegistration接口，主要是为了将组件注册到MBeanServer上方便通过jmx进行管理。从上图可以看到，基本上tomcat所有的组件都会继承这个类来做管理

2.Container、Executor、Server、Service接口，继承了Lifecycle接口，同时自己又定义了自己所属类型组件需要的方法接口，例如：

Server下可以定义多个Service、定义shutdown的port、address、全局的命名空间、上下文、资源等，tomcat都需要对其进行操作，因此会抽象出这些方法，如下图

![](Tomcat源码分析—Lifecycle生命周期\server-i.jpg)

Service同理，可定义多个connector、container、多个线程池executor、查找父组件Server等

![](Tomcat源码分析—Lifecycle生命周期\service-i.jpg)

Container定义的接口就比较多了，比较重要的就是对子容器的操作了

![](Tomcat源码分析—Lifecycle生命周期\container-i.jpg)

ContainerBase实现了Container接口，实现了Container接口中的方法，定义了Map children来存储子容器，作用和LifecycleBase有些类似，这里就不贴代码结构了，其他的如Context、Engine、Host、Wrapper接口都继承子Container接口，且定义了各自需要的一些接口方法，很方便的让具体的实现去扩展。例如：StandardContext既要纳入lifecycle生命周期管理、又要注册jmx、还要具有Container和Context的功能怎么办？

根据上面的说明，tomcat这种灵活的组件设计，只需要让StandardContext继承ContextBase抽象类，实现Context接口即可。