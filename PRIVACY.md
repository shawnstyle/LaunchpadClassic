# Privacy / 隐私说明

Launchpad Classic is a local application launcher. It has no account login, telemetry, advertising tracking, remote analytics, or network upload.

Launchpad Classic 是本机应用启动器，不提供账号登录、遥测、广告追踪、远程分析或网络上传。

## Data read locally / 在本机读取的数据

- App names, paths, bundle identifiers, and icons from standard app directories and locations explicitly added by the user, so apps can be displayed and launched.
  为展示和启动应用，扫描标准应用目录及用户主动添加的位置，读取名称、路径、应用标识和图标。
- The current screen's desktop wallpaper, used as the launcher background.
  为展示启动器背景，读取当前屏幕的桌面壁纸。
- Search text and pointer events processed during interaction.
  在运行期间处理搜索文字及交互指针事件。

## Data saved locally / 在本机保存的数据

Layouts, folder names and members, and additional app locations are stored locally through macOS UserDefaults. Login-at-startup is enabled only through an explicit user action. Preferences are not included in source or release packages and are not uploaded to GitHub.

应用排列、文件夹名称与成员、额外应用位置等偏好设置通过 macOS UserDefaults 保存在本机。登录启动需要用户主动启用。偏好设置不包含在源码或发布包中，也不会上传到 GitHub。

Optional interaction logs are for development troubleshooting. Standard public builds disable them. App inventories, preferences, desktop screenshots, credentials, and debug logs should not be committed or attached to public releases.

可选交互日志仅用于开发排查，标准公开构建默认关闭。不应将应用清单、偏好设置、桌面截图、凭据或调试日志提交到公开仓库或发布附件。

## Release contents / 发布内容

Public builds use a generic bundle identifier. Release packaging includes only the required application bundle files and does not copy extended attributes, resource forks, AppleDouble files, or local project metadata. The checksum file verifies download integrity.

公开版使用通用应用标识。发布包仅包含应用运行需要的 bundle 文件，不复制扩展属性、资源叉、AppleDouble 文件或本机工程元数据。校验文件用于核对下载完整性。

## Public GitHub identity / GitHub 公开身份

The repository owner and commit usernames remain public GitHub information. Public commits use a GitHub noreply address; email privacy does not make the account anonymous.

仓库所有者账号与提交用户名仍属于 GitHub 公开信息。公开提交使用平台 noreply 隐私邮箱；邮箱隐私不等于账号匿名。
