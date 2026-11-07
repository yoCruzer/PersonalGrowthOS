# G1专用用户Debug探针工程证据

本目录证明受限探针实现、签名包与离线审查，不证明真实CloudKit或G1通过。原生39/39、工具13/13、独立原生3/3及loopback5/5；两端签名构建/实包校验通过，unsigned Mac Release通过。

独立发现并关闭：错误run/dataset/命令身份结果、iOS结果覆盖、重复启动共享store、umask077导致跨用户文件不可读、非原子请求发布，以及token进入argv。初始红例、测试夹具路径规范化失败与最终绿测均保留，见independent-review/review-final.md。

真实测试必须独立比对账户、run、dataset、指令摘要、逐mutation和PNG原字节，并检查pending与events。结果字段PASS只是命令执行与快照完成，不能直接当云验收计数。

临时签名包和本机桥配置不入仓库；桥仅127.0.0.1并用临时token，凭据文件仅原用户和指定haha用户可读。真实CloudKit尚未执行。

实现提交`2dfbafb`的远端定向CI已通过：Xcode27.1、工具13/13、原生39/39和unsigned iOS Simulator构建。见[ci-accepted.json](ci-accepted.json)；不替代真实云验证。
