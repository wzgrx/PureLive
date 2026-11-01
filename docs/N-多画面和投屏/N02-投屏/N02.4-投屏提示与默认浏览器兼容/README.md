# N02.4 投屏提示与默认浏览器兼容

来源：#126新增回复。

应用内采集提示可切为紧凑；保留本地停止入口，不隐藏系统隐私提示；复现默认Chromium到Android的ICE候选、权限和局域网行为，按根因实现兼容，不要求关闭浏览器隐私。

用户授权所有决定自行处理，按本方案推进，无需重复确认。系统权限仍由系统处理。

## 各布局

手机使用设置列表和标准返回，桌面复用设置面板，电视保留遥控焦点和返回边界。用户可见新文字进入zh/en有序翻译。默认外观保持不变，配置不持有账号、Cookie或媒体签名。

## 验收

实际协议或官方响应证据、对应回归、必要的修改前失败、受控原生布局与运行验证。原设备未覆盖与受控证据分开记录。

## 实现要点

提示提供完整、紧凑停止按钮、隐藏应用提示三档；默认完整，非法导入值回到可见默认。等待本机授权时所有模式均显示；隐藏后本地遥控页仍有停止按钮，系统隐私提示不受影响。视图回归覆盖切换、停止和授权等待取消。

默认Chromium156无自定义浏览器参数：原始host候选均为.local；使用同一接收端本地Binding后得到数字srflx候选。方案按RFC8489的Binding子集实现，只回复已配对来源IPv4、固定32字节、请求上限576字节、每秒100包、拒绝未知必须理解属性，随接收端关闭；端口只在认证status返回。无第三方STUN/TURN，没有媒体中继，也不要求关闭mDNS隐私。配对撤销/重配、UDP端口释放和畸形帧回归通过；最终同源Android原生视频连接与截图/录制尚需验证，不以纯候选探针代替视频验收。

主资料：https://www.rfc-editor.org/rfc/rfc8489.html；Chromium mDNS策略：https://chromium.googlesource.com/chromium/src/+/376fc41e87a058f7a7b300b0ec3a4982b4ec0960/components/policy/resources/templates/policy_definitions/Miscellaneous/WebRtcLocalIpsAllowedUrls.yaml。
