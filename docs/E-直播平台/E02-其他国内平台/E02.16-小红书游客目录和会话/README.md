# E02.16 小红书游客目录和会话

2026-11-04：旧适配器关于“没有公开目录”的推断已经失效。匿名官网提供全部、游戏、才艺颜值、生活分享、兴趣手工、科技财经、运动户外；编号从分类接口读取。

游客目录仍需网页签名。普通HTTP直接请求实测406；公开页面SSR只有目录状态，列表由接口返回。隔离短时网页获得当前SDK签名与游客RWP身份，随后关闭网页，由原生播放器和WebSocket负责播放、弹幕与统计。目录每个请求有独立游标，尾游标重复时结束。原接口按房间号/分享链接进房和受限检查保留。

参考：https://github.com/cv-cat/catbus/blob/master/src/platforms/xhs/web/push.ts （只核对协议，独立实现）；https://github.com/llg1634/xhs-live-recorder-extension/blob/main/extension/content_final_main.js （只核对事件编码）；官网游客实际请求与独立RWP握手。没有借用他人账号或发言制造测试消息。

首版实现、专项回归、API37原生联调和最终all/14门禁已通过；其他系统的新游客链路和物理设备仍待验。Linux没有现成WebView后端，继续提供分享链接播放并明确提示游客目录和弹幕不可用。Apple与物理电视属于单独验证层，不用单元测试代替。
