# 正式 Development 执行入口交付证据

最终源码40文件由 trusted-source-sha256.json、编译快照和 runtime-final/unsigned-source-receipt.json 绑定。本机完整包156/156 PASS（24协议、17准备器、115 SDK/host），最低iOS17 SDK编译PASS/运行NOT_RUN，38项实际打包检查PASS。local/ 保留真实日志，早期145项中的测试字段数误计失败和修正后5项定向通过没有覆盖原件。

独立复核：review-ledger-runner/ 为20项（11 ledger+9 runner），review-runtime-boundaries/ 为9项独立（同次另有21项作者测试，共30，不称30项独立），review-production-entry/ 为6项新增入口审查。此前报告各自固定源码；远端工作流会把35项独立测试在最新源码统一运行。runtime的合成CMS是原创负例，没有Owner的profile、证书、私钥、设备或业务记录。CI移植只将该合成fixture路径改为显式环境变量，不改变断言。

runtime-final/ 记录最终已签候选：严格codesign验证通过，实际inspect-runtime exit0/SELF_QUALIFICATION_PASS，自身签名/profile/设备、OS会话、Application Support全部true；网络调用0，账户资格/服务访问NOT_RUN，Owner批准和P0均false。实际原始profile与签名输出留在仓库外。runtime-actual/ 是前一个中间候选，runtime-intermediate-observations.json保留此前拒绝；设备不可用后来通过的原因未证明，不追认旧失败。

owner-window-proposal.json只是审阅请求，缺少有效批准窗口且不能被执行入口接受。实际enrollment、Keychain anchor、账户和CloudKit请求均未执行。最终签名二进制SHA256为9291c390e9dbbf8b6999dbe06b87f45769be53f4e76744e7f5139298c867577e。下一步是当前候选远端CI及Owner测试会话/固定Development窗口，不重跑G1或占用手机。

固定源码107963d的定向CI42467777146和产品CI42467777172均SUCCESS；原始ZIP摘要、merge checkout68a637b、40源pins及实际计数已核验，见ci-foundation-107963d/verification.json与ci-product-107963d/verification.json。Owner已批准一次真实Development窗口且确认测试会话；批准条件CI现已满足，已提供haha启动脚本，实际执行结果待接收，不重复请求许可。
