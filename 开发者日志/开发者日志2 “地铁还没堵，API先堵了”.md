![开发者日志2 “地铁还没堵，API先堵了” 1](https://img2-tc.tapimg.com/moment/etag/FoLwIgIio3-7fdxir3TQJ8u6z0cU_20261007215419.png/_tap_ugc.jpg)

![开发者日志2 “地铁还没堵，API先堵了” 2](https://img2-tc.tapimg.com/moment/etag/FnlpJ4f_reEl6Rw_Ii5xmyoWpQA8_20261007215423.png/_tap_ugc.jpg)

# 开发者日志2 “地铁还没堵，API先堵了”

10/07

明天要上早八了，这次的小故事就让GPT小姐全讲完吧😋

图片第一张是lbr刚刚画的局内效果预期图，后面是dsh给的实机Demo

![horizontal line](https://img.tapimg.com/market/images/3ae50dc2fa28859c37e75e0fb018ab2b.png)![horizontal line](https://img.tapimg.com/market/images/d7712bfef1565701241fe3b6fa37db20.png)

昨天还在说“这次一定不删新建文件夹”。

今天新建文件夹还在。

项目也确实跑起来了。

虽然过程和我想象中的“跑起来”稍微有一点区别。

前一天把《涌线—crowd line》的方向定下来以后，我就开始画局内效果。

其实画得还挺开心的。

因为这个游戏从一开始就不是那种“角色很可爱、场景很精致”的路线。我们没有美术，甚至连比较完整的视觉方案都还没有，所以我干脆先从玩家在一局游戏里到底应该看到什么开始想。

最中间是一张不断变化的地铁线网。

线是活的，客流也是活的。

站点会积压，线路会拥堵，换乘会形成潮汐。玩家做出的每一个操作，都应该能在画面上留下痕迹。

所以我先随手画了一个预期中的局内效果。

左上角放时间、天气和资源。

右上角放运营指标。

中间是线网。

下面是玩家真正能做的事情：限流、加车、封站、跳站、广播。

听起来很简单。

但我越画越觉得，这个游戏最重要的东西其实不是这些按钮。

而是——

按下按钮以后，整个系统有没有“活起来”。

比如一条线路晚点。

不是弹出来一句：

> “XX线路发生拥堵。”

然后数字减五。

而是应该看到一团客流慢慢聚起来，站点颜色越来越热，换乘节点开始膨胀，随后拥堵沿着线路向外扩散。

玩家再去限流。

客流真的被截住。

另一边却开始变得更拥挤。

这才是我想要的“涌线”。

所以第一版效果图里，我把大量注意力放在了线路、节点、客流和反馈上。

然后问题来了。

![horizontal line](https://img.tapimg.com/market/images/3ae50dc2fa28859c37e75e0fb018ab2b.png)![horizontal line](https://img.tapimg.com/market/images/d7712bfef1565701241fe3b6fa37db20.png)

我不会做这种东西。

准确来说，不是完全不会。

而是如果按照正常开发流程来做：

画UI → 写地图 → 写乘客 → 写寻路 → 写调度 → 写各种状态 → 做动画 → 做特效……

等这一套做完，估计gamejam都结束了。

于是我开始尝试一个之前没有认真用过的东西：

DeepSeek Harness。

简称 DSH。

想法也很朴素：

既然现在 AI 已经可以直接参与工程，那为什么不让它帮我把第一版东西搓出来？

于是我把需求、截图、一些乱七八糟的描述扔进去。

然后开始了漫长的——

人与第三方小作坊 API 的斗智斗勇。

😋

第一次用 DSH，很多东西其实都不熟。

而且这次接的还是第三方 API。

有时候你觉得自己已经把需求说得非常清楚了，它：

“好的，我理解了。”

然后生成出来的东西：

好的，它理解了。

就是理解成了另一个东西。

改。

再改。

再让它改。

改完以后发现上一个能跑的地方没了。

再改。

API又抽风。

继续改。

一度让我产生一种非常熟悉的感觉：

> 我是不是又在用另一种方式新建文件夹？

不过折腾了一晚上以后，至少有一个东西出来了。

它真的跑起来了。

![horizontal line](https://img.tapimg.com/market/images/3ae50dc2fa28859c37e75e0fb018ab2b.png)![horizontal line](https://img.tapimg.com/market/images/d7712bfef1565701241fe3b6fa37db20.png)

和效果图当然差得很远。

这是目前实际跑出来的第一版 Demo。

第一眼看过去，甚至有点简陋。

和前面的预期效果图比，UI没有做完，线路表现也还很粗糙，客流更像一颗颗会移动的点。

但我盯着它看了一会儿，突然觉得：

这东西至少已经开始像个游戏了。

线路会动。

节点会聚集。

客流会沿着线路走。

不同颜色的线路之间会产生关系。

而且最重要的是——

我开始可以真的去想：

“如果这里多加一辆车，会发生什么？”

“如果这个站限流，会不会把压力推给下一个换乘站？”

“如果我把一个站封掉，整张网会怎么重新组织？”

这时候我才第一次感觉到，前几天策划案里写的那些东西，不再只是 Word 里的漂亮话了。

![horizontal line](https://img.tapimg.com/market/images/3ae50dc2fa28859c37e75e0fb018ab2b.png)![horizontal line](https://img.tapimg.com/market/images/d7712bfef1565701241fe3b6fa37db20.png)

当然，现在离“涌现式地铁调度沙盒”还差得远。

目前这个 Demo 更像是：

先把一张线网和一群会动的东西放进同一个屏幕里。

距离真正的乘客行为、路径选择、拥挤、从众、换乘、耐心值，以及最后那些我们最想看到的“自己涌出来的问题”，还有很多东西要补。

但我觉得第一步反而没有必要一次做到。

因为这次我们已经提前踩过一次坑了。

不要一开始就想着把最终版本做出来。

先让它动。

再让它像游戏。

然后再让它变成我们真正想做的游戏。

![horizontal line](https://img.tapimg.com/market/images/3ae50dc2fa28859c37e75e0fb018ab2b.png)![horizontal line](https://img.tapimg.com/market/images/d7712bfef1565701241fe3b6fa37db20.png)

还有一个很有意思的地方。

第一天我画效果图的时候，想的是：

> “我要做一个很有感觉的地铁调度游戏。”

今天第一次看到 Demo 跑起来的时候，想的却变成了：

> “这里堵起来以后会不会很好玩？”

我觉得这可能就是从画游戏到做游戏的区别。

效果图负责让我知道终点在哪里。

Demo 负责告诉我：

这条路到底能不能走。

至少现在看来。

能走。

虽然路上全是坑。

而且其中一部分坑还是 DSH 帮我挖的。

![horizontal line](https://img.tapimg.com/market/images/3ae50dc2fa28859c37e75e0fb018ab2b.png)![horizontal line](https://img.tapimg.com/market/images/d7712bfef1565701241fe3b6fa37db20.png)

所以今天的成果大概可以总结成：

预期效果图：有了。

实机 Demo：有了。

完整玩法：没有。

漂亮 UI：没有。

Bug：有。

第三方 API：还活着。

新建文件夹：没有删。

这就够了。

下一步继续把“会动的线网”往“会自己出问题的线网”推进。

毕竟我们真正想做的，从来不是一个地铁线路播放器。

而是让玩家看着屏幕，然后突然喊一句：

“坏了，怎么全堵了？”

然后自己想办法把它救回来。![horizontal line](https://img.tapimg.com/market/images/3ae50dc2fa28859c37e75e0fb018ab2b.png)![horizontal line](https://img.tapimg.com/market/images/d7712bfef1565701241fe3b6fa37db20.png)

[#TapTap聚光灯游戏创作挑战](https://www.taptap.cn/hashtag/taptap%E8%81%9A%E5%85%89%E7%81%AF%E6%B8%B8%E6%88%8F%E5%88%9B%E4%BD%9C%E6%8C%91%E6%88%98) [#TapTap聚光灯](https://www.taptap.cn/hashtag/TapTap%E8%81%9A%E5%85%89%E7%81%AF) [#聚光灯gamejam开发者日志](https://www.taptap.cn/hashtag/%E8%81%9A%E5%85%89%E7%81%AFGameJam%E5%BC%80%E5%8F%91%E8%80%85%E6%97%A5%E5%BF%97)


