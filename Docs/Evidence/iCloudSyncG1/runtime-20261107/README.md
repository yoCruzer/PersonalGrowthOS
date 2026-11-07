# G1单Mac真实Development运行证据

已签名SyncLab在Owner专用haha用户运行，仅固定合成dataset。13条命令验证账户访问、文字及68字节PNG保存、真实CKSyncEngine发送确认、持久状态、Store/Engine重开和再次同步，以及独立对象的新增→修改→逻辑删除。每次同步pending清空，完整mutation历史和PNG原字节保持。独立13组断言及20个内存篡改负控通过。

这不是双设备G1验收：未从空白存储独立重建，重开是同进程Store/Engine重开而不是进程崩溃。FETCH事件不提供逐record来源。iPhone有线/配对/开发者模式正常，但安装在开发镜像个性化12040/12051/TatsuError4处失败；Owner确认重启、重连、首次解锁后仍复现。官方设备支持更新返回无匹配27B52包。已准备同一已签名Debug IPA并获准尝试Apple Configurator；安装结果另行记录，不能提前计为PASS。

原始请求字节保存在requests；results只移除了私有账户指纹并标记移除。summary保存私有原件SHA，原件仅留本机。独立审查脚本需要本机原始结果才能复算账户一致性，不把脱敏输出冒称原件。[独立审查](independent-review/review.md)说明全部限制。

正式产品回归42332546608为FAIL：Release/Unit成功，UI smoke 3PASS/2FAIL，仍为短名称单行高度断言。先前42332154418因后续提交被取消，不能当作PASS。SyncLab定向CI42332149355仍为39/39、13/13及模拟器构建PASS。

最终安装尝试：商店确认窗口没有确认按钮，Owner核实一致，重开重试仍失败，Configurator未安装。probe-014停止引擎回执PASS、快照不变；临时loopback已关闭。独立审查覆盖001–013，014为收尾核验，不计入独立审查的13组。恢复需创建新临时通道及启动包，原始测试事实不重置。
