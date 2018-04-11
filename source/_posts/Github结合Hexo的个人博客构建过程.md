---
title: Github结合Hexo的个人博客构建过程
tags: [github, hexo, blog, nodejs]
date: 2017-11-04 17:18:37
updated: 2017-11-04 17:18:37
categories: [教程]
---
博客环境终于搭建好了，想了好久写点什么作为第一篇文章，最终决定将这个博客的创建过程记录下来，大部分内容百度下都有，这里我重点记录需要注意的地方，其他内容简单记录下。废话不多说了，直接上正文！

### 前言
[Hexo](https://hexo.io/) 是一个简单地、轻量地、基于NodeJS的一个静态博客框架。通过Hexo我们可以快速创建自己的博客，仅需要几条命令就可以完成。
发布时，Hexo可以部署在github上面。可以省去服务器的成本，还可以减少各种系统运维的麻烦事(系统管理、备份、网络)。

### Github准备
首先得注册github账号，这个就不用多说了，然后在自己的账号上创建一个仓库，我这里直接取名为[blog](https://github.com/bingli-borland/blog.git)

### NodeJS安装
由于hexo是基于nodejs，因此得首先安装nodejs, 这里我直接安装windows版本，下载地址
版本：node-v8.7.0-win-x64.zip
<!--more-->
### Hexo安装
node-v8.7.0自带了npm工具，无需额外安装。
安装Hexo

```
E:\project> npm install -g hexo-cli
```

### 博客工程创建
初始化博客工程blog文件夹

```
E:\project> hexo init blog
```

进入blog目录，创建一篇博客

```
E:\project\blog> hexo new "My New Post"
```

生成静态文件
```
E:\project\blog> hexo generate
```

启动hexo

```
E:\project\blog> hexo server
```

部署博客到githup的配置

```
deploy:
  type: git
  repo: git@github.com:bingli-borland/blog.git
  branch: gh-pages
```

部署命令

```
E:\project\blog> hexo deploy
```

### 需要注意的地方
主要是_config.xml文件的配置：
- 通过ssh的方式访问github，因此需要生成秘钥添加到自己的github上
- root这个属性，默认为/，但是这样生成的静态文件引入的js、css、图片等资源都没有一个统一的前缀，例如：index.html里引入了这个css样式文件:  < link href="/css/main.css?v=5.1.3" rel="stylesheet" type="text/css" /> ，但是在没有配置单独域名的情况下，部署到github上然后访问https://bingli-borland.github.com/blog/， debug查看这个资源实际上是 https://bingli-borland.github.com/css/main.css?v=5.1.3 不存在这个资源，404错误，如果配置了单独的域名映射到这个http://bingli-borland.github.com/blog/ 地址，不会出现这个问题。所以在没有单独域名的情况下有一个解决方案：配置root: /blog，这样生成的静态文件引入的js、css、图片等资源都有一个统一的前缀/blog，例如：index.html里引入了这个css样式文件< link href="/blog/css/main.css?v=5.1.3" rel="stylesheet" type="text/css" />，这样访问https://bingli-borland.github.com/blog/ 不会出现404问题，访问正常。其他大部分配置在具体主题的_config.xml下配置。


