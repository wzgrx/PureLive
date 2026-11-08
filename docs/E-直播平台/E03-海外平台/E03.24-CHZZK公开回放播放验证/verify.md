# E03.24 CHZZK公开回放播放验证

目录与公开 HLS 有实测；同一个录像从 UPLOAD 转 ABR_HLS 后不再给 HLS。Accept: application/dash+xml 可取得 XML，远端 FFmpeg 读 MPD 失败，本地 MPD 的端到端解码仍未通过。HLS 试验提交 de5219d5 保留本地研究分支；不进入 5.6.5，后续核对分片和本地代理后再验收。
