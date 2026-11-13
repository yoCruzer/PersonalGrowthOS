# 可直接填写的本地化字段

`zh-Hans.json` 与 `en-US.json` 包含名称、副标题、宣传文本、描述、关键词和同一英文审核说明。正式名称沿用“随心log”，不新建App或改变Bundle ID。

按Apple当前字段限制检查：name/subtitle各30字符、promotionalText170字符、description4000字符、keywords100字节、reviewNotes4000字节。Apple产品页营销说明与后台参考对关键词的单位表述不同，本材料采用更严格的UTF-8 100字节限制；简体中文91字节、英文100字节。最终仍以后台校验为准。校验命令：`python3 Scripts/AppStore/validate_materials.py`。

分类建议：主要Lifestyle（与现有工程category一致）、次要Productivity。下载价格0；首发Manually release this version。Owner已确认目标大陆、香港、澳门、台湾、美国，核实准入后保存，不默认全球。What’s New不用于首个版本。版权字段及审核联系人不编造，后台已有值先核对；公开支持邮箱justincookiec@outlook.com已获准并展示；GitHub Pages已部署验证。

可直接填写：

| 字段 | 简体中文 | 英文 |
| --- | --- | --- |
| Support URL | https://yocruzer.github.io/PersonalGrowthOS/support-zh.html | https://yocruzer.github.io/PersonalGrowthOS/support-en.html |
| Privacy Policy URL | https://yocruzer.github.io/PersonalGrowthOS/privacy-zh.html | https://yocruzer.github.io/PersonalGrowthOS/privacy-en.html |
| Marketing URL | https://yocruzer.github.io/PersonalGrowthOS/ | 同左 |

版权建议2026 Guangzong Cai，仍需本人确认；审核电话由Owner直接提供给Apple，不写入这里。

依据：[平台版本字段](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)、[产品页面](https://developer.apple.com/app-store/product-page/)。
