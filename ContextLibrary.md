# Caldera项目上下文库

## 项目概述

Caldera是一个网络安全平台，旨在自动化对手模拟、辅助手动红队操作和自动化事件响应。它基于MITRE ATT&CK框架构建。

## 核心组件

### 1. 核心系统
- 异步命令与控制(C2)服务器
- REST API接口
- Web界面

### 2. 插件系统
插件扩展了核心框架的功能，提供了额外的功能，如代理、报告、TTP集合等。

## 关键服务和它们之间的关系

### app_svc.py (应用服务)
- **功能**: 管理应用程序的核心功能，如插件加载、代理信任管理、操作调度等
- **与其他文件的关系**: 
  - 与data_svc.py协作存储和检索数据
  - 与contact_svc.py协作处理代理通信
  - 与file_svc.py协作处理文件操作

### data_svc.py (数据服务)
- **功能**: 管理所有数据对象(代理、能力、对手、操作等)的存储、检索和持久化
- **与其他文件的关系**:
  - 为app_svc.py提供数据存储和检索功能
  - 与rest_svc.py协作处理REST API请求的数据操作
  - 为所有API处理程序提供数据访问

### rest_svc.py (REST服务)
- **功能**: 处理REST API请求，包括创建、更新、删除各种对象(代理、能力、操作等)
- **与其他文件的关系**:
  - 与data_svc.py协作执行数据操作
  - 与app_svc.py协作执行应用级操作
  - 为API处理程序提供业务逻辑实现

## 主要API接口和服务

### 代理相关API (/api/v2/agents)
- GET /agents - 获取所有代理
- GET /agents/{paw} - 根据ID获取特定代理
- POST /agents - 创建新代理
- PATCH /agents/{paw} - 更新代理
- DELETE /agents/{paw} - 删除代理

### 能力相关API (/api/v2/abilities)
- GET /abilities - 获取所有能力
- GET /abilities/{ability_id} - 根据ID获取特定能力
- POST /abilities - 创建新能力
- PUT /abilities/{ability_id} - 更新或创建能力
- DELETE /abilities/{ability_id} - 删除能力

### 操作相关API (/api/v2/operations)
- GET /operations - 获取所有操作
- GET /operations/{id} - 根据ID获取特定操作
- POST /operations - 创建新操作
- PATCH /operations/{id} - 更新操作
- DELETE /operations/{id} - 删除操作

### 对手相关API (/api/v2/adversaries)
- GET /adversaries - 获取所有对手配置
- GET /adversaries/{adversary_id} - 根据ID获取特定对手配置
- POST /adversaries - 创建新对手配置
- PUT /adversaries/{adversary_id} - 更新或创建对手配置
- DELETE /adversaries/{adversary_id} - 删除对手配置

## 插件示例

### access插件
- **功能**: 提供红队初始访问工具和技术
- **主要文件**: plugins/access/app/access_api.py

### atomic插件
- **功能**: 集成Atomic Red Team项目TTPs
- **主要文件**: plugins/atomic/app/atomic_svc.py

## 数据模型

### Agent (代理)
- 表示连接到Caldera服务器的终端代理
- 包含属性如平台、架构、执行器、信任状态等

### Ability (能力)
- 表示可在目标系统上执行的单个技术
- 包含执行器、需求、权限级别等信息

### Operation (操作)
- 表示一次完整的红队操作
- 包含对手配置、代理组、计划等信息

### Adversary (对手)
- 表示一个对手配置文件
- 包含一系列按特定顺序执行的能力

## 配置管理

### 主要配置文件
- conf/default.yml - 默认配置文件
- 包含API密钥、联系信息、插件配置等

### 环境要求
- Python 3.9+
- 推荐8GB+内存和2+ CPUs
- 推荐安装GoLang 1.17+以动态编译GoLang代理

## 安全注意事项

Caldera团队强烈建议在安全环境/网络中部署Caldera服务器，不要将其暴露在互联网上。