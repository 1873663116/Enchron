# 浏览与来源的外部约束

本文记录 `Modules/Emby`、`Modules/MediaLibrary` 与 `Modules/MediaSource` 里**无法从代码本身读出**的事实：Emby 服务器的数据形状、visionOS 列表与滚动的实测行为、以及文件浏览导航栈与字节流的边界。

## Emby 服务器的数据形状

- **递归 item 查询返回每一个后代**。库的顶层要显示整部作品，因此必须过滤，否则一部剧的各季会与剧本身并排。
- **一个能播的标题带着一个 media source 并描述自己；剧与季没有**——Emby 把流放在集上。把各集的 sources 传进来，是这些页面能说出与电影页同样的话的唯一办法，而且说的是这一整季持有的**每一个不同值**，而不是拿一集代表全部。
- **每条轨道一个 stream**，同一语言因此重复出现；About 块读作语言列表而不是轨道列表。季会把同一份轨道列表按集重复一遍，所以要去重。
- **文件级事实对季不成立**。大小、总码率与发布版本属于一个文件；季不是文件，那些字段在季上被丢掉，只保留每集共有的容器。
- **一个发布可以带两条自述完全相同的轨道**，因此轨道列表按下标建立身份，而不是按内容。
- **Dolby Vision 的 profile 与 codec profile 是两件事**：后者命名比特流的编码工具，前者命名 Dolby Vision 的层与元数据如何封装、以及不理解它们的播放器还能否得到正确画面。每一个 Dolby Vision 发布同时也是 Main 10，所以 codec profile 单独区分不了它们。
- **Emby 4.9.5 的 PlaybackInfo 暴露 source size，但不暴露 media-source ETag**。因此 item 的 ETag 加上 source size 是可得的最强内容信号，`VersionedMediaIdentity` 据此判断内容是否变了。
- **服务器给一个 source 的名字就是磁盘上的文件名**，也就是发布组的 release string——既不可读又远超一个站在 Play 旁边的控件所能容纳。版本选择器因此自己组织"这一版值得说出口的东西"：画面多大、怎么编码、有没有广色域。
- **图片端点带内容标签**。`ArtworkStore` 的键包含 server image tag，换了封面就是另一个键。

## 媒体受理与容器

- **`FileFilter.playable` 按容器受理，`MediaDiscoveryAdmissionPolicy.mediaFiles` 不列任何基本流扩展名**。裸的 `.dts` 与 `.thd` 因此永远不会出现在库里，DTS 与 TrueHD 要被编码矩阵打开，只能以 Matroska 封装入库。`Scripts/verification/regression_preparation_adapter.py` 的 format-corpus 必需固件集据此选片。

## 凭据表单与系统 Save-Password 面板

- **Emby 连接表单声明 `textContentType(.username)` 与 `textContentType(.password)`，提交它会引出系统的 Save-Password 面板**。WebDAV 与 SMB 的连接表单同样如此：产品提交的每一个凭据表单都会引出这张面板。见 `Scripts/verification/regression_preparation_adapter.py` 与 `Scripts/rules/test_regression_preparation_adapter.py`。
- **这张面板在窗口层级之外**，同一个 Preparation 里后续的任何一步都清不掉它。每个连接分支因此在自己的连接按钮之后立刻关掉它，一次关闭只能顶一个分支。见 `Scripts/verification/regression_preparation_adapter.py`。

## 详情页的滚动

详情页只有两个位置：显示它的图片，或显示标题之下的分节。两者之间的一切是它经过的地方，不是它停留的地方。

- **落点交给系统自己的交接点**。在那里调整目标，页面就按系统的曲线减速到位；自己动手会在手势还在跑时把页面从它底下拉走。
- **系统在解析任何滚动目标时都会问这个类型**，不只在本页的手势结束时。一个刚从正被滚动的 shelf 推入的页，会在那股上行动量还在手上时被问到；据实回答会把一个没人碰过的页直接送过它的图片。**在这一页被滚动过之前，它在哪里就是它该在的地方。**
- **`scrollPosition` 要配置到顶边，而不是不设**。页面分批到达——先是条目，然后是集，然后是特辑、相关作品与演职员——每一次到达都让内容更高。SwiftUI 只在位置**自报**时才承诺跨内容尺寸变化保持稳定，一个未设的位置什么都没说，页面会随填充向下漂。佩戴者一旦滚动，SwiftUI 把他们的位置写进来，这条就不再适用。
- **页面一直跑到窗口自己的顶边、在导航栏之下**，好让它为返回控件留出的空间是自己的。从上面借来的必须在下面还回去，否则页尾够不到。
- **背景图不是滚动内容**：它站着不动并淡出，分节从它上面升起而不是把它拖上去。它以全强度抵达每一条窗口边缘——在边缘淡它的 alpha 不会柔化任何东西，只会让页面自身的浅色表面透出来，图片最后被镶上一圈白边。窗口的圆角是它唯一需要的边。
- **标题下的压暗用椭圆而不是径向渐变**。径向渐变在每个方向按同一半径淡出，在一个远宽于高的框里，到框缘时它仍然不透明，于是在图片上画出一条直线。

## visionOS 列表与滚动的实测行为

- **`ScrollView` 会把离开视口的 cell 画到窗口边缘之外**，所以页面渲染必须显式约束在页面内。
- **每个库是自己的屏幕**。不这样做，在两个库之间切换会复用视图并留住上一个库存在 `@State` 里的 view model。
- **侧栏目的地之间没有方向**，因此交叉淡入。动画由 `ZStack` 承载：挂在那个变化的 `.id` **之上**的修饰符会与它一起重建，什么都不会动画。
- **一个 `Section` 会吞掉它内部每一行的标识符**（设备实测）。需要分组又需要行可寻址时，用分隔线而不是 Section。
- **`Picker` 把系统勾选标记画在尾缘**，那是原生菜单的习惯。手工写 `Label(systemImage: "checkmark")` 会把标记放到标题前面，并把每一个标题右推。
- **集按它在季里的编号排序**。按名字排会把 "Episode 10" 放在 "Episode 2" 前面；而在集带真实标题的剧里，按名字排出来的顺序毫无意义。
- **换季时旧集留在屏幕上**，新的一季在后面加载。先清空会让那一行塌陷，把它下面的一切上移再下移。行的身份跟随**屏幕上真实的集**而不是菜单选中的季，淡入因此发生在新集到达时。
- **多列信息用网格而不是行**。各列长度不同，网格让每一列都从同一条左边缘与同一条基线开始，不论页面放得下几列。

## 明文 HTTP 与 App Transport Security

- **iOS 17 一代起，ATS 默认拒绝一切以 IP 地址为主机的明文加载**。自建 Emby 与 WebDAV 正是这种地址：佩戴者输入一串数字，没有域名，也没有为任何名字签发的证书。`Config/Enchron-Info.plist` 因此设 `NSAllowsArbitraryLoads`，这是唯一能覆盖无法预先枚举的地址的键。
- **`NSAllowsLocalNetworking` 只豁免回环、RFC 1918 与链路本地地址**。100.64.0.0/10（Tailscale 等 CGNAT）与任何公网 IP 都不在其中，它们会以 `NSURLErrorDomain -1022` 被拒。
- **`NSAllowsArbitraryLoads` 在被 `NSAllowsLocalNetworking`、`NSAllowsArbitraryLoadsInWebContent` 或 `NSAllowsArbitraryLoadsForMedia` 中任意一个同时声明时被系统忽略**，取默认值 NO。三者并存的 plist 读起来是放行的，实际拦截每一个可路由地址，既无编译警告也无运行日志。[`Scripts/rules/check_ats_cleartext_policy.py`](../Scripts/rules/check_ats_cleartext_policy.py) 断言这一点。
- **ATS 的拒绝不描述服务器**。`-1022` 说明的是本 App 的传输策略，不是对端要求 HTTPS；把它当作“请改用 https://”的依据，会把佩戴者指向一个只讲明文的端口。`RemoteConnectionFailureDiagnoser` 因此只凭 TLS 握手探测下判断。

## 文件浏览的导航栈

- **栈里存的是逻辑查询键，不是显示路径**。本地根必须与加载器在空栈时首次列出用的那个逻辑根一致；在这里播下绝对路径，会让 `navigateUp` / `navigateForward` / 面包屑回根去查询一个来源不认识的键，返回一个空的根。
- **进入文件夹开启新分支**，前进历史随即作废。
- **列表增量更新**：成功才替换，并保留稳定的 UUID 让 SwiftUI 只做 diff 而不重建整张列表；原地刷新失败时保留现有条目、只呈现错误，列表不会跳成空的。合并按 `uniquingKeysWith` 进行，因为数据源可能返回重复 ID，不去重会崩。
- **换层级先清空**：合并是就地增量，条目一直留到替换清单到达，所以离开一个层级时 `enterLevel()` 先丢掉 `files` 与 `folders`；否则新层级淡入的是上一层的行。这条只针对层级切换，同一层级的刷新仍然保留条目。
- **层级的落定与呈现分离**：`currentLevelHasSettled` 表示当前层级的清单已到达终态——列出成功、列出为空、或列出失败。`loadFiles` 的远程与本地两条终点都调用 `settleCurrentLevel()`，连接与选根的失败分支同样调用，否则一个失败的层级永远不落定、页面永远不淡入。层级身份是 `(sourceGeneration, activeDataSource?.id, currentRemotePath)`：换源与换根都经 `beginSourceGeneration()`，因此不必再比对根路径。呈现侧怎么用这个信号见 `docs/DESIGN_SYSTEM_CONSTRAINTS.md` 的「层级切换的过渡」。
- **没有层级缓存**：向上返回与前进历史都重新列出，落定前该层级是空的。缓存能让返回在第 0 帧就落定，但要先定义失效（删除、新建、重连、换源），目前没有实现。
- **浏览来源时 Manage 菜单整颗禁用**：菜单里四项（Add Files、Add from Photos、Add Folder、New Library Folder）全部作用于媒体库，在来源层级里点下去不是空操作，而是把文件夹建到、把文件导到一个屏幕没有显示的地方。远程来源也不支持 mkdir／删除／重命名，适配器只有列目录与取字节。把远程文件送进媒体库的通道保留在卡片右键的 “Add to Media Library”。DEBUG 选择通道在来源分支返回空列表，与灰显一致。
- **排序作用于整个层级**：`applySortToLevel()` 同时排文件与文件夹，由排序观察者与 `loadFiles` 的两条终点调用；文件夹仍然整体排在文件之前。此前只有文件被排，而来源按自己的顺序返回文件夹（WebDAV 是服务器的顺序，本地是 `contentsOfDirectory` 的顺序），所以一个以文件夹为主的层级对排序控件毫无反应。断言见 `MediaLibraryUIStateTests.sharedSortStateOrdersFolders`。
- **文件夹按名字与时间排，不按体积**：文件夹自身没有体积，读出它要爬完整棵子树——WebDAV 要么 `Depth: infinity`（多数服务器默认关闭）要么逐层 PROPFIND，请求数等于子树节点数；SMB 与本地要递归遍历。排序是一个即时动作，不该在按下的那一刻发起这种爬取，因此体积键下文件夹按名字排，只跟随升降序。虚拟标签（媒体库文件夹）的成员体积虽然就在内存里，也不按内容合计排，否则同一个键在同一个页面的两支里是两种量。
- **文件夹的修改时间来自来源，缺失时沉底**：WebDAV 用集合响应里的 `getlastmodified`（RFC 4918 不强制集合携带它，缺失即 nil）；SMB 用目录项自己的 `modifiedAt`，根一级的共享没有；本地在 `contentsOfDirectory` 的 keys 里要 `.contentModificationDateKey`。语义是目录条目发生增删的时间，不是内容最后被改的时间——新一集落进季文件夹，季文件夹就会浮到前面。时间键下没有时间的文件夹排在末尾（升降序都一样），同时间的按名字排且两个方向都保持名字升序。虚拟标签用自己的 `LibraryFolder.createdAt`；这个字段是后加的，老数据解码为 nil、同样沉底，不用成员的最新时间去伪造。
- **这一层回答不了的排序键以禁用呈现**：判定在 `FileBrowsingDomain.SortKeyAvailability`——名称永远可用；时间在层级里没有任何条目携带时间时不可用；体积在层级里没有文件时不可用（纯文件夹的层级）。禁用**不改写用户存下来的选择**：带着体积键走进纯文件夹层级，偏好仍是体积、那一行仍带对勾但灰显，显示顺序是名字（这正是体积键对文件夹的含义），走回有文件的层级它自己重新生效；导航不静默修改用户的设置。断言见 `LevelSortingTests`。

## 字节流与来源身份

- **`contentLength` 以 range read 的回答为准**，打开之前的那个只是提示；大小是来源此刻的回答，不是浏览目录时留下的数字。
- **demux 策略在来源注册为可播放时就被捕获**。非缓存模式让 demuxer 填到它较短的时长目标，除非先撞上前向字节安全上限；缓存模式的时长目标实际上无界，因此前向字节上限才是正常的停止条件，某些来源另有自己的字节上限。
- **容器打开区间只有一个**，它结束之后的所有读取都是媒体读取。这条边界是远程读取记账的分界线。
- **图片先完成原子磁盘写，再在内存里暴露**，避免读者看到半张图。
- **句柄释放时，回环服务器要取消这个登记的所有传输**。服务器只在下一次 `send` 失败时才知道对端已经关闭，而 `send` 要等当前这一块（1 MiB）的来源读取返回；在慢速网盘上，一个已关闭条目留下的读取会占住共享 `URLSession` 每主机连接上限（未设置 `httpMaximumConnectionsPerHost`，取系统默认，iOS 系为 4，未在 visionOS 上实测）中的一个，直到那一块读完，下一个条目的打开就排在它后面。`unregister(token:)` 因此按 token 取消传输任务与连接，响应循环在每次读取前检查取消；`MediaByteStreamReleaseTests.releasingTheHandleCancelsAnUnansweredRead` 钉住这条契约。仍在登记内、但对端已经关闭的连接（AVFoundation 的探测请求）还是要等当前一块读完才结束，每次打开约一到两个。
- **回环服务器缓存的端口只在监听器 ready 期间有效**。系统可以在 App 挂起期间收走这个监听器，而登记铸出的 `http://127.0.0.1:<port>/…` 只是个数字，所以 `failed` 与 `cancelled` 连同监听器一起清掉端口（并取消它名下的连接与传输），下一次 `register` 因此经 `ensureStarted` 起一个新的监听器；`waiting` 只清端口，此刻到达的登记留在 `startupWaiters` 里等下一次 ready 或 failed。此前铸出的句柄留在死端口上，不再复活。每次状态变化记为 `bytestream.listener.state=<ready|failed:<error>|cancelled|waiting:<error>> port=<n>`；`MediaByteStreamListenerTests.aRegistrationAfterTheListenerDiedServesFromANewListener` 钉住这条契约。
- **产品在来源被添加时收到一次地址，此后在它打开的会话存续期间一直向那个路径发请求**。移动端点的激活会由产品已绑定的会话应答，注入的每一个故障因此都会带上同一个签名。见 `Scripts/rules/test_regression_remote_source.py`。

## Emby 交给播放核心的只有字节

- **流地址不带容器扩展名**：`/Videos/{id}/stream?Static=true&MediaSourceId=…`。Emby 对带扩展名与不带扩展名的地址回同一份字节（在真实服务器上核对过一部正常 MP4 与一部 Container 标成 mpegts 的 M2TS），带上扩展名只会把服务器自述的容器名塞进地址；`MediaSources[].Container` 会错，播放核心自己从内容判定容器，所以它在 `EmbyMediaSource` 上只是展示信息，缺失也不阻止播放。
- **服务器自述的视频编码不预先拒绝播放**。以前 `EmbyPlaybackBridge` 用 Emby 报的 codec 名对照一张自己的白名单，在打开之前就抛错；那张表与播放核心的解码判定是两份会漂移的真相，而且自述可以错。现在编码是否可放由播放核心打开字节后判定，Emby 与本地文件走同一条路、得到同一种 "Unable to Play"。断言见 `Tests/EmbyPackageTests/EmbyPlaybackBridgeTests.swift` 的 `declaredCodecDoesNotGatePlayback`。
- **同一个文件经本地、共享（SMB／WebDAV 登记真实文件名）、Emby（登记无扩展名的服务器名字、经 `EmbyMediaByteSource` 取字节）三种形态送进播放核心，核心报出的编码、尺寸、时长、帧率、音轨、字幕轨、起播与 seek 落点必须完全一致**。任何一条路和本地不一样，就是中转链掉了东西。断言见 `Tests/EnchronApp/PlaybackSourceAndAudioSessionTests.swift` 的 `testTheSameFileReachesThePlaybackCoreIdenticallyThroughEveryRoute`（MKV 多轨与 MP4 各跑三条路，不依赖外部服务）与 `testTheSameFileReachesThePlaybackCoreIdenticallyThroughTheLiveShares`（真实的 WebDAV 与 SMB 测试服务：读 `test-services/{webdav,smb}/runtime.json` 的身份，经 `WebDAVDataSourceAdapter`／`SMBDataSourceAdapter` 连接、列目录、取播放源，用 WebDAV 回归集合与 SMB 共享都持有的 `sdr-bframe-aggregate-30s.mkv`；两个 runtime.json 缺一即跳过，服务由 `Scripts/verification/ensure_test_services.py` 维护）。

## SMB 与 WebDAV 的形状

- SMB 连接后**共享在根一级仍然表现为文件夹**，服务器本身是来源根；以 `$` 结尾的管理/隐藏共享被过滤掉。
- 从完整的 rootPath 路径换算到相对共享的路径，是这两个适配器与来源根之间唯一的坐标转换。
- **WebDAV 集合路径的尾斜杠是身份的一部分**：严格的服务器对 `/dav/regression` 回 404、对 `/dav/regression/` 回 207。适配器把 `"/"` 换算成已验证基地址时要用 `URLComponents.path`，`URL.path` 会丢掉尾斜杠。断言见 `WebDAVDataSourceAdapterTests` 的 `rootListingKeepsTheCollectionSlash`。
- **只回自己的 PROPFIND 是一个空目录**：`Depth: 1` 的响应里只有集合自身时，先补尾斜杠重试一次——严格的服务器对不带尾斜杠的地址就是这么回的；重试后仍然只有自己，就当作空目录返回空清单。这里无法把「空目录」和「忽略 Depth 的服务器」区分开，选择前者：空目录是每天都会遇到的，而把它抛成错误会让每一个空的叶子目录都弹一次报错。断言见 `WebDAVDataSourceAdapterTests` 的 `emptyCollectionListsAsEmpty`。

## 卡片时长的来源

- 目录列表只给体积，不给时长；时长只能从容器头读出。`MediaSourceProbe.information(for:)`（PlaybackCore）用 FFmpeg 打开来源、取 `MediaSourceInformation.durationSeconds` 后立即关闭，不建播放会话。远程文件走与播放相同的 `resolvePlayableSource` 与字节流服务，探测结束后 `release()` 句柄；MKV 只读头部几百 KB，moov 在尾部的 MP4 会多一次尾部读。
- 探测在 `loadProgressForFiles`／`loadViewingStatesForCurrentFolder` 之后按目录顺序逐个进行，只针对没有观看状态也没有已知时长的文件，目录切换（`sourceGeneration`／引用列表变化）即停止；这里比的是条目 ID 的集合而不是顺序，否则探测途中改一次排序就把已经拿到的观看状态与时长全部丢掉。结果经 `PlaybackLaunchCoordinator.recordKnownDuration` 写入 `PersistedMediaState.knownDurationSeconds`，之后不再探测。
- `knownDurationSeconds` 与观看状态独立：`ViewingStatePolicy` 对短于 15 分钟的内容不保存观看状态，但时长仍是事实；播放会话结束时也把探到的时长写进同一字段。没有观看状态、只有时长的文件，App 侧的 provider 返回位置 0 的 `VideoCardViewingState`，列表视图对位置 0 且未完成的记录不显示续播标记。


## 封面缓存的编码

- 远程封面落盘时按 `CGImage.alphaInfo` 选格式：带透明通道的存 PNG，不带的存 JPEG（0.72）。Emby 的 Logo 图是带透明通道的 PNG（2026-09-05 从服务器直接验证：Evangelion 的 Logo 743×306 RGBA，74% 像素透明），统一存成 JPEG 会把透明区域压成白色，第二次打开详情页标题就带白框。
- `ArtworkKey(remoteImageURL:)` 的散列输入带 `alpha-aware|` 前缀，旧的 JPEG 副本因此被绕开而不是被读回；它们留在 Caches 里由系统回收。
