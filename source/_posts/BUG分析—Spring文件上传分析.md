---
title: BUG分析—Spring文件上传分析
date: 2019-05-17 15:11:03
updated: 2019-05-17 15:11:03
tags: [spring, java, tomcat, upload]
categories: [BUG分析]
---

### 前言

最近客户应用上传文件失败了，场景如下：
spring应用，配置如下：

web.xml

``` xml
<?xml version="1.0" encoding="UTF-8"?>
<web-app xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://java.sun.com/xml/ns/javaee" xsi:schemaLocation="http://java.sun.com/xml/ns/javaee http://java.sun.com/xml/ns/javaee/web-app_3_0.xsd" id="WebApp_ID" version="3.0">
    ........
  <context-param>
    <param-name>contextConfigLocation</param-name>
    <param-value>classpath*:META-INF/spring/spring.xml</param-value>
  </context-param>
  <listener>
    <listener-class>
	            org.springframework.web.context.ContextLoaderListener
   </listener-class>
  </listener>
  <listener>
    <listener-class>org.springframework.web.util.IntrospectorCleanupListener</listener-class>
  </listener>
  <servlet>
    <servlet-name>springmvc</servlet-name>
    <servlet-class>org.springframework.web.servlet.DispatcherServlet</servlet-class>
    <init-param>
      <param-name>contextConfigLocation</param-name>
      <param-value>classpath*:META-INF/spring/spring-context.xml</param-value>
    </init-param>
    <load-on-startup>1</load-on-startup>
  </servlet>
  <servlet-mapping>
    <servlet-name>springmvc</servlet-name>
    <url-pattern>/</url-pattern>
  </servlet-mapping>
    .......
</web-app>
```

<!-- more -->

spring.xml

``` xml
<?xml version="1.0" encoding="UTF-8"?>
<beans .....>
.....
<bean id="multipartResolver"
			class="org.springframework.web.multipart.support.StandardServletMultipartResolver"></bean>
....	
</beans>

```

spring-context.xml没有关于上传文件相关的配置。

根据参考文献，我们知道，spring配置上传文件主要Resolver为StandardServletMultipartResolver和CommonsMultipartResolver，详细见参考。但是在应用中的逻辑确实：

``` java
@RequestMapping({"/uploadZipFile"})
  @ResponseBody
  public JSONObject uploadZipFile(HttpServletRequest request)
  {
.......
    MultipartResolver resolver = new CommonsMultipartResolver(request.getSession().getServletContext());
    MultipartHttpServletRequest multipartRequest = resolver.resolveMultipart(request);
    MultipartFile xlsFile = multipartRequest.getFile("filename");
    JSONObject params = new JSONObject();
    InputStream in = null;
    FileOutputStream out = null;

    byte[] bs = new byte[5021];

    int len = -1;
    if (xlsFile != null) {
      try {
        in = xlsFile.getInputStream();

        out = new FileOutputStream("/home/bes/download/upload.zip");

        while (in.read(bs) != -1) {
          out.write(bs);
        }
        in.close();
        out.flush();
        out.close();
      } catch (Exception e) {
        e.printStackTrace();
      }
    }
    return params;
  }

```

### DispatchServlet中MultipartResolver处理

DispatchServlet每次接受请求，都会通过checkMultipart判断multipartResolver是否存在以及这个请求是不是上传文件的请求，如果过是，则调用multipartResolver的resolveMultipart处理文件流数据：

``` java
  protected HttpServletRequest checkMultipart(HttpServletRequest request)
    throws MultipartException
  {
    if ((this.multipartResolver != null) && (this.multipartResolver.isMultipart(request))) {
      if (WebUtils.getNativeRequest(request, MultipartHttpServletRequest.class) != null) {
        this.logger.debug("Request is already a MultipartHttpServletRequest - if not in a forward, this typically results from an additional MultipartFilter in web.xml");
      }
      else if (request.getAttribute("javax.servlet.error.exception") instanceof MultipartException) {
        this.logger.debug("Multipart resolution failed for current request before - skipping re-resolution for undisturbed error rendering");
      }
      else
      {
        return this.multipartResolver.resolveMultipart(request);
      }
    }

    return request;
  }
```

这里发现上面的问题：代码中用CommonsMultipartResolver处理文件流，但是spring.xml中还配置了StandardServletMultipartResolver来自动处理文件流，即DispatchServelt中对multipartResolver。这会造成一个明显的问题：StandardServletMultipartResolver先处理，CommonsMultipartResolver后处理但是已经拿不到结果，最后文件上传失败。但是实际情况是在tomcat7当中没有问题，tomcat8失败了，什么情况？只有debug了。

### 问题分析

先看看StandardServletMultipartResolver.resolveMultipart

``` java
public MultipartHttpServletRequest resolveMultipart(HttpServletRequest request) throws MultipartException
  {
    return new StandardMultipartHttpServletRequest(request, this.resolveLazily);
  }
public StandardMultipartHttpServletRequest(HttpServletRequest request, boolean lazyParsing)
    throws MultipartException
  {
    super(request);
    if (!lazyParsing)
      parseRequest(request);
  }
private void parseRequest(HttpServletRequest request)
  {
    try
    {
      Collection parts = request.getParts();//关键位置，看具体web容器实现
      this.multipartParameterNames = new LinkedHashSet(parts.size());
      MultiValueMap files = new LinkedMultiValueMap(parts.size());
      for (Part part : parts) {
        String filename = extractFilename(part.getHeader("content-disposition"));
        if (filename != null) {
          files.add(part.getName(), new StandardMultipartFile(part, filename));
        }
        else {
          this.multipartParameterNames.add(part.getName());
        }
      }
      setMultipartFiles(files);
    }
    catch (Exception ex) {
      throw new MultipartException("Could not parse multipart servlet request", ex);
    }
  }

```

tomcat7-Request.getParts

``` java
    @Override
    public Collection<Part> getParts() throws IOException, IllegalStateException,
    ServletException {

        parseParts();

        if (partsParseException != null) {
            if (partsParseException instanceof IOException) {
                throw (IOException) partsParseException;
            } else if (partsParseException instanceof IllegalStateException) {
                throw (IllegalStateException) partsParseException;
            } else if (partsParseException instanceof ServletException) {
                throw (ServletException) partsParseException;
            }
        }

        return parts;
    }

    private void parseParts() {

        // Return immediately if the parts have already been parsed
        if (parts != null || partsParseException != null) {
            return;
        }
        //web.xml中servlet是否配置了<multipart-config>
        MultipartConfigElement mce = getWrapper().getMultipartConfigElement();

        if (mce == null) {
            //没有配置，context是否配置allowCasualMultipartParsing=true
            if(getContext().getAllowCasualMultipartParsing()) {
                mce = new MultipartConfigElement(null,
                        connector.getMaxPostSize(),
                        connector.getMaxPostSize(),
                        connector.getMaxPostSize());
            } else {
                //没有则返回空list，即可以先不处理文件流，可以等到业务中手动处理
                parts = Collections.emptyList();
                return;
            }
        }
		// 后续逻辑是真正处理part
    }
```

tomcat8-Request.getParts

``` java
    @Override
    public Collection<Part> getParts() throws IOException, IllegalStateException,
            ServletException {

        parseParts(true);

        if (partsParseException != null) {
            if (partsParseException instanceof IOException) {
                throw (IOException) partsParseException;
            } else if (partsParseException instanceof IllegalStateException) {
                throw (IllegalStateException) partsParseException;
            } else if (partsParseException instanceof ServletException) {
                throw (ServletException) partsParseException;
            }
        }

        return parts;
    }

    private void parseParts(boolean explicit) {

        // Return immediately if the parts have already been parsed
        if (parts != null || partsParseException != null) {
            return;
        }

        Context context = getContext();
        //web.xml中servlet是否配置了<multipart-config>
        MultipartConfigElement mce = getWrapper().getMultipartConfigElement();

        if (mce == null) {
            //没有配置，context是否配置allowCasualMultipartParsing=true
            if(context.getAllowCasualMultipartParsing()) {
                mce = new MultipartConfigElement(null,
                                                 connector.getMaxPostSize(),
                                                 connector.getMaxPostSize(),
                                                 connector.getMaxPostSize());
            } else {
                //此处为true，直接抛出必须配置<multipart-config>的异常
                if (explicit) {
                    partsParseException = new IllegalStateException(
                            sm.getString("coyoteRequest.noMultipartConfig"));
                    return;
                } else {
                    //没有则返回空list，即可以先不处理文件流，可以等到业务中手动处理
                    parts = Collections.emptyList();
                    return;
                }
            }
        }
        // 后续逻辑是真正处理part
    }
```

bes9.2-Request.getParts

``` java
  public Collection<Part> getParts() throws IOException, ServletException {
    checkMultipartConfiguration("getParts");
    return getMultipart().getParts();
  }
  //web.xml中servlet是否配置了<multipart-config>
  private void checkMultipartConfiguration(String name)  {
    if (!isMultipartConfigured())
      throw new IllegalStateException(sm.getString("coyoteRequest.multipart.not.configured", name));
  }
  private Multipart getMultipart() {
    if (this.multipart == null) {
      this.multipart = new Multipart(this, this.coyoteRequest.getParameters(), this.wrapper.getMultipartLocation(), this.wrapper.getMultipartMaxFileSize(), this.wrapper.getMultipartMaxRequestSize(), this.wrapper.getMultipartFileSizeThreshold());
    }

    return this.multipart;
  }
  public synchronized Collection<Part> getParts() throws IOException, ServletException
  {
    if (!isMultipart()) {
      throw new ServletException("The request content-type is not a multipart/form-data");
    }

    initParts();

    if (null == this.unmodifiableParts) {
      this.unmodifiableParts = Collections.unmodifiableList(this.parts);
    }

    return this.unmodifiableParts;
  }
  //判断是否是文件上传请求
private boolean isMultipart() {
    if (!this.request.getMethod().toLowerCase(Locale.ENGLISH).equals("post")) {
      return false;
    }
    String contentType = this.request.getContentType();
    if (contentType == null) {
      return false;
    }

    return contentType.toLowerCase(Locale.ENGLISH).startsWith("multipart/form-data");
  }
//真正处理parts
  private void initParts()
    throws IOException, ServletException
  {
    if (this.parts != null) {
      return;
    }
    this.parts = new ArrayList();
    try {
      RequestItemIterator iter = new RequestItemIterator(this, this.request);
      while (iter.hasNext()) {
        RequestItem requestItem = iter.next();
        PartItem partItem = new PartItem(this, requestItem.getHeaders(), requestItem.getFieldName(), requestItem.getContentType(), requestItem.isFormField(), requestItem.getName(), this.request.getCharacterEncoding());

        Streams.copy(requestItem.openStream(), partItem.getOutputStream(), true);

        String fileName = partItem.getFileName();
        if ((fileName == null) || (fileName.length() == 0))
        {
          this.parameters.addParameter(partItem.getName(), partItem.getString());
        }

        this.parts.add(partItem);
      }
    } catch (SizeException ex) {
      throw new IllegalStateException(ex);
    }
  }
```



综上分析由于没有配置<multipart-config>和allowCasualMultipartParsing=true，所以tomcat7中表现为StandardServletMultipartResolver并没有真正的处理，等到业务中处理文件流。

但是tomcat8就直接抛出异常了，而且即使配置了<multipart-config>，目前explicit对spring来说并不可配，所以StandardServletMultipartResolver处理之后，业务中也不能拿到文件。

在bes9.2中的表现首先是必须要配置<multipart-config>，否则会抛出异常。配置之后则表现和tomcat8配置<multipart-config>之后一样，业务也不能拿到文件。

这个问题的关键点是StandardServletMultipartResolver和CommonsMultipartResolver混合同时使用，实际DispatchServlet只能接受一个multipartResolver对象，因此只能使用其中一个。

### 参考
http://www.cnblogs.com/tengyunhao/p/7670293.html
https://www.cnblogs.com/ceshi2016/p/8421624.html







