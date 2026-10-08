# 《涌线--crowd line》线路池设计

根据策划案v0.2的难度分级，为四个池各推荐4条线路网，并附JSON数据文件。JSON格式遵循策划案第14节的简化原则：只保留线路拓扑、换乘关系、站点名称和特色标签。

## 基础池（★）：1—2条线，5—8个站

### 池1-1：温州S1+S2（已指定）

温州轨道交通S1线全长53.51公里，18座车站，海蓝色；S2线全长63.32公里，20座车站，大红色。两条线在灵昆站和机场站换乘，是典型的市域快轨网络。S1串联温州南站、龙湾国际机场；S2沟通乐清辅城、瓯江口新城、瑞安辅城。

```json
{
  "name": "温州S1+S2",
  "city": "温州",
  "difficulty": "★",
  "duration": 300,
  "target_score": 1000,
  "lines": [
    {
      "id": "S1",
      "name": "S1线",
      "color": "#1E90FF",
      "stations": ["桐岭","潘桥","动车南","新桥","德政","龙霞路","惠民路","三垟湿地","龙腾路","科技城","瑶溪","奥体中心","永中","机场","灵昆","瓯江口","瓯华","双瓯大道"]
    },
    {
      "id": "S2",
      "name": "S2线",
      "color": "#DC143C",
      "stations": ["清东路","旭阳路","万岙","盐盆","新望","翁垟","柳市东","灵昆","机场","永兴","沙城","天河","海城","鲍田","大典下","汀田","莘塍","上望","上东路","东山"]
    }
  ],
  "transfers": [
    {"station": "灵昆", "lines": ["S1","S2"]},
    {"station": "机场", "lines": ["S1","S2"]}
  ],
  "features": ["市域快轨", "跨瓯江", "机场线", "沿海走廊"]
}
```

### 池1-2：里斯本蓝线

单线，18站，欧洲经典地铁，海滨城市，适合新手熟悉操作。

```json
{
  "name": "里斯本蓝线",
  "city": "里斯本",
  "difficulty": "★",
  "duration": 300,
  "target_score": 1000,
  "lines": [
    {
      "id": "Az",
      "name": "蓝线",
      "color": "#1E90FF",
      "stations": ["Reboleira","Amadora Este","Alfornelos","Pontinha","Carnide","Colégio Militar","Alto dos Moinhos","Laranjeiras","Jardim Zoológico","Praça de Espanha","São Sebastião","Parque","Marquês de Pombal","Avenida","Restauradores","Baixa-Chiado","Terreiro do Paço","Santa Apolónia"]
    }
  ],
  "transfers": [],
  "features": ["欧洲经典", "海滨城市", "单线教学"]
}
```

### 池1-3：成都都江堰M-TR有轨电车（特色线路）

都江堰M-TR旅游客运专线全长约20.33公里，共设28座车站（其中5座预留）。线路从雪山脚下出发，串联青城山高铁站、都江堰景区、万达主题公园和熊猫谷等重要景区。是国内首个轨道交通裸眼3D宣传片的取景地，宛如一条银色丝带蜿蜒于雪山与古城之间。

```json
{
  "name": "都江堰M-TR",
  "city": "成都",
  "difficulty": "★",
  "duration": 300,
  "target_score": 1000,
  "lines": [
    {
      "id": "M-TR",
      "name": "都江堰旅游专线",
      "color": "#2E8B57",
      "stations": ["青城山高铁站","青城山景区","东软学院","中兴","石厂湾","都江堰景区","南桥","灌县古城","玉垒山","离堆公园","万达主题公园","熊猫谷","八角庙"]
    }
  ],
  "transfers": [],
  "features": ["有轨电车", "雪山景观", "熊猫谷", "青城山", "旅游专线"]
}
```

### 池1-4：哥本哈根M1+M2

两条线共用市中心段，然后分岔，是典型的北欧简约风格。

```json
{
  "name": "哥本哈根M1+M2",
  "city": "哥本哈根",
  "difficulty": "★",
  "duration": 300,
  "target_score": 1000,
  "lines": [
    {
      "id": "M1",
      "name": "M1线",
      "color": "#00CED1",
      "stations": ["Vanløse","Flintholm","Lindevang","Fasanvej","Frederiksberg","Forum","Nørreport","Kongens Nytorv","Christianshavn","Islands Brygge","DR Byen","Sundby","Bella Center","Ørestad","Vestamager"]
    },
    {
      "id": "M2",
      "name": "M2线",
      "color": "#FFD700",
      "stations": ["Vanløse","Flintholm","Lindevang","Fasanvej","Frederiksberg","Forum","Nørreport","Kongens Nytorv","Christianshavn","Amagerbro","Lergravsparken","Øresund","Amager Strand","Femøren","Kastrup","Lufthavnen"]
    }
  ],
  "transfers": [
    {"station": "Vanløse", "lines": ["M1","M2"]},
    {"station": "Flintholm", "lines": ["M1","M2"]},
    {"station": "Lindevang", "lines": ["M1","M2"]},
    {"station": "Fasanvej", "lines": ["M1","M2"]},
    {"station": "Frederiksberg", "lines": ["M1","M2"]},
    {"station": "Forum", "lines": ["M1","M2"]},
    {"station": "Nørreport", "lines": ["M1","M2"]},
    {"station": "Kongens Nytorv", "lines": ["M1","M2"]},
    {"station": "Christianshavn", "lines": ["M1","M2"]}
  ],
  "features": ["北欧简约", "机场线", "共用走廊", "无人驾驶"]
}
```

## 进阶池（★★）：3—5条线，15—25个站，3—5个换乘站

### 池2-1：香港荃湾线+观塘线+港岛线

三条核心线，换乘站密集，早晚高峰潮汐明显。

```json
{
  "name": "香港核心三线",
  "city": "香港",
  "difficulty": "★★",
  "duration": 480,
  "target_score": 3000,
  "lines": [
    {
      "id": "TWL",
      "name": "荃湾线",
      "color": "#FF0000",
      "stations": ["荃湾","大窝口","葵兴","葵芳","荔景","美孚","长沙湾","深水埗","太子","旺角","油麻地","佐敦","尖沙咀","金钟","中环"]
    },
    {
      "id": "KTL",
      "name": "观塘线",
      "color": "#00A040",
      "stations": ["黄埔","何文田","油麻地","旺角","太子","石硖尾","九龙塘","乐富","黄大仙","钻石山","彩虹","九龙湾","牛头角","观塘","蓝田","油塘","调景岭"]
    },
    {
      "id": "ISL",
      "name": "港岛线",
      "color": "#0075C2",
      "stations": ["坚尼地城","香港大学","西营盘","上环","中环","金钟","湾仔","铜锣湾","天后","炮台山","北角","鲗鱼涌","太古","西湾河","筲箕湾","杏花邨","柴湾"]
    }
  ],
  "transfers": [
    {"station": "太子", "lines": ["TWL","KTL"]},
    {"station": "旺角", "lines": ["TWL","KTL"]},
    {"station": "油麻地", "lines": ["TWL","KTL"]},
    {"station": "金钟", "lines": ["TWL","ISL"]},
    {"station": "中环", "lines": ["TWL","ISL"]}
  ],
  "features": ["维多利亚港", "潮汐流", "换乘枢纽", "跨海段"]
}
```

### 池2-2：武汉2号线+4号线

两条跨江线，换乘站少但客流大。

```json
{
  "name": "武汉跨江双线",
  "city": "武汉",
  "difficulty": "★★",
  "duration": 480,
  "target_score": 3000,
  "lines": [
    {
      "id": "2",
      "name": "2号线",
      "color": "#FF69B4",
      "stations": ["天河机场","航空总部","宋家岗","巨龙大道","盘龙城","宏图大道","常青城","金银潭","常青花园","长港路","汉口火车站","范湖","王家墩东","青年路","中山公园","循礼门","江汉路","积玉桥","螃蟹岬","小龟山","洪山广场","中南路","宝通寺","街道口","广埠屯","虎泉","杨家湾","光谷广场","珞雄路","华中科技大学","光谷大道","佳园路","光谷火车站","佛祖岭"]
    },
    {
      "id": "4",
      "name": "4号线",
      "color": "#FFD700",
      "stations": ["武汉火车站","杨春湖","工业四路","仁和路","园林路","罗家港","铁机路","岳家嘴","东亭","青鱼嘴","楚河汉街","洪山广场","中南路","梅苑小区","武昌火车站","首义路","复兴路","拦江路","钟家村","汉阳火车站","五里墩","七里庙","十里铺","王家湾","玉龙路","永安堂","孟家铺","黄金口","新天","集贤","知音","新农","凤凰山","蔡甸广场","临嶂大道","柏林"]
    }
  ],
  "transfers": [
    {"station": "洪山广场", "lines": ["2","4"]},
    {"station": "中南路", "lines": ["2","4"]}
  ],
  "features": ["跨长江", "潮汐明显", "光谷通勤", "换乘集中"]
}
```

### 池2-3：宁波12号线跨海市域铁路+4号线+7号线（特色线路）

宁波轨交12号线是国内首条跨海市域（郊）铁路，全长61.5公里，设车站10座，北起鄞州区小洋江站，向南跨过象山港后止于大目湾站。全线控制性工程象山港跨海大桥长8.3公里，与甬莞高速公路桥并行，形成“双桥卧波”和“海上列车”的独特景致。采用最高时速160公里的A型4编组列车，主城至象山县最快约30分钟可达。

```json
{
  "name": "宁波跨海线",
  "city": "宁波",
  "difficulty": "★★",
  "duration": 480,
  "target_score": 3000,
  "lines": [
    {
      "id": "12",
      "name": "12号线跨海线",
      "color": "#00CED1",
      "stations": ["小洋江","云龙","横溪","塘溪","咸祥","松岙","贤庠","大徐","丹城","大目湾"]
    },
    {
      "id": "4",
      "name": "4号线",
      "color": "#FFA500",
      "stations": ["慈城","官山河","长兴路","金山路","奥体中心","洪塘中路","洪塘","庄桥火车站","丽江路","双东路","翠柏里","大卿桥","柳西","宁波火车站","兴宁桥西","兴宁桥东","白鹤","儿童公园","矮柳","潘火路","嵩江东路","南高教园区","金达南路","小洋江","东钱湖"]
    },
    {
      "id": "7",
      "name": "7号线",
      "color": "#9370DB",
      "stations": ["俞范","明海大道","贵驷","骆驼北","金华路","宝轴西路","康桥南路","湾头","大剧院","外滩大桥","曙光","体育馆","福民公园","新天路","民安路","北明程路","盛莫路","邱隘","小洋江","云龙"]
    }
  ],
  "transfers": [
    {"station": "小洋江", "lines": ["4","7","12"]},
    {"station": "云龙", "lines": ["12","7"]}
  ],
  "features": ["跨海铁路", "海上列车", "双桥卧波", "看海地铁", "象山海鲜"]
}
```

### 池2-4：台北淡水信义线+板南线

十字交叉，市中心换乘压力大。

```json
{
  "name": "台北十字线",
  "city": "台北",
  "difficulty": "★★",
  "duration": 480,
  "target_score": 3000,
  "lines": [
    {
      "id": "R",
      "name": "淡水信义线",
      "color": "#FF0000",
      "stations": ["淡水","红树林","竹围","关渡","忠义","复兴岗","北投","奇岩","唭哩岸","石牌","明德","芝山","士林","剑潭","圆山","民权西路","双连","中山","台北车站","中正纪念堂","东门","大安森林公园","大安","信义安和","台北101/世贸","象山"]
    },
    {
      "id": "BL",
      "name": "板南线",
      "color": "#0000FF",
      "stations": ["顶埔","永宁","土城","海山","亚东医院","板桥","府中","江子翠","龙山寺","西门","台北车站","善导寺","忠孝新生","忠孝复兴","忠孝敦化","国父纪念馆","市政府","永春","后山埤","昆阳","南港","南港展览馆"]
    }
  ],
  "transfers": [
    {"station": "台北车站", "lines": ["R","BL"]},
    {"station": "民权西路", "lines": ["R"]},
    {"station": "中山", "lines": ["R"]},
    {"station": "中正纪念堂", "lines": ["R"]},
    {"station": "西门", "lines": ["BL"]},
    {"station": "忠孝新生", "lines": ["BL"]},
    {"station": "忠孝复兴", "lines": ["BL"]}
  ],
  "features": ["十字线网", "淡水河", "台北101", "夜市通勤"]
}
```

## 硬核池（★★★）：8条线以上，50+站，10+换乘站

### 池3-1：重庆轨道交通全网（已指定）

截至2026年2月，重庆轨道交通已开通13条线路，包括环线、1号线、2号线、3号线（含空港线）、4号线、5号线、6号线、国博线、9号线、10号线、18号线、江跳线、璧铜线，运营里程约593千米，共设车站271座，其中换乘站50座。

重庆的穿楼（2号线李子坝站）、跨江（多座跨江大桥）、山地起伏、单轨与地铁混跑，天然适合做拥堵和涌现。2号线采用跨座式单轨，3号线同样为单轨，地形落差大，换乘站复杂。

```json
{
  "name": "重庆轨道交通全网",
  "city": "重庆",
  "difficulty": "★★★",
  "duration": 720,
  "target_score": 6000,
  "lines": [
    {
      "id": "1",
      "name": "1号线",
      "color": "#DC143C",
      "stations": ["朝天门","小什字","较场口","七星岗","两路口","鹅岭","大坪","石油路","歇台子","石桥铺","高庙村","马家岩","小龙坎","沙坪坝","杨公桥","烈士墓","磁器口","石井坡","双碑","赖家桥","微电园","陈家桥","大学城","尖顶坡","璧山"]
    },
    {
      "id": "2",
      "name": "2号线",
      "color": "#228B22",
      "stations": ["较场口","临江门","黄花园","大溪沟","曾家岩","牛角沱","李子坝","佛图关","大坪","袁家岗","谢家湾","杨家坪","动物园","大堰村","马王场","平安","大渡口","新山村","天堂堡","建桥","金家湾","刘家坝","白居寺","鱼洞"]
    },
    {
      "id": "3",
      "name": "3号线",
      "color": "#FFD700",
      "stations": ["鱼洞","金竹","鱼胡路","学堂湾","大山村","花溪","岔路口","九公里","麒龙","八公里","二塘","六公里","五公里","四公里","南坪","工贸","铜元局","两路口","牛角沱","华新街","观音桥","红旗河沟","嘉州路","郑家院子","唐家院子","狮子坪","重庆北站南广场","重庆北站北广场","童家院子","翠云","园博园","鸳鸯","金渝","金童路","回兴","双龙","碧津","江北机场T2航站楼","举人坝"]
    },
    {
      "id": "4",
      "name": "4号线",
      "color": "#FF8C00",
      "stations": ["黄岭","石船","桐梓林","果园","鱼嘴","雁坪","王家城","太平冲","港城","黑石子","寸滩","保税港","头塘","海尔路","民安大道","重庆北站北广场","嘉州路","洪湖东路","龙溪","石马河立交"]
    },
    {
      "id": "5",
      "name": "5号线",
      "color": "#00CED1",
      "stations": ["悦港北路","悦港大道","椿萱大道","中央公园西","中央公园","中央公园东","鲁家沟","丹鹤","湖霞街","重光","和睦路","人和","幸福广场","冉家坝","大龙山","大石坝","忠恕沱","红岩村","歇台子","石桥铺","石新路","巴山","凤西路","重庆西站","华岩寺","华成路","半山","中梁山","金建路","华岩中心","跳磴"]
    },
    {
      "id": "6",
      "name": "6号线",
      "color": "#9370DB",
      "stations": ["茶园","邱家湾","长生桥","刘家坪","上新街","小什字","大剧院","黄泥磅","红土地","五里店","江北城","大剧院","小什字"]
    },
    {
      "id": "9",
      "name": "9号线",
      "color": "#87CEEB",
      "stations": ["高滩岩","天梨路","沙坪坝","小龙坎","土湾","红岩村","富华路","化龙桥","李家坪","蚂蝗梁","观音桥","鲤鱼池","刘家台","江北城","五里店","溉澜溪","头塘","保税港","何家梁","石盘河","上湾路","青岗坪","宝圣湖","兴科大道","春华大道","兰桂大道","中央公园东","从岩寺","花石沟"]
    },
    {
      "id": "10",
      "name": "10号线",
      "color": "#FF69B4",
      "stations": ["兰花路","南湖","万寿路","后堡","七星岗","大礼堂","曾家岩","鲤鱼池","红土地","龙头寺公园","重庆北站南广场","重庆北站北广场","民心佳园","三亚湾","上湾路","环山公园","长河","T3航站楼","T2航站楼","渝北广场","鹿山","中央公园东","中央公园","中央公园西","悦来","王家庄"]
    },
    {
      "id": "18",
      "name": "18号线",
      "color": "#20B2AA",
      "stations": ["跳磴南","跳磴","石坪桥","杨家坪","滩子口","黄桷坪","四川美术学院","电厂","李家沱大桥","李家沱","花溪工业园","外河坪北","外河坪南","简家岩","长江二桥","富华路"]
    },
    {
      "id": "环线",
      "name": "环线",
      "color": "#FF4500",
      "stations": ["重庆图书馆","沙坪坝","天星桥","马家岩","高庙村","石桥铺","陈家坪","谢家湾","奥体中心","体育公园","动步公园","冉家坝","洪湖东路","民安大道","重庆北站南广场","五里店","弹子石","涂山","仁济","海棠溪","罗家坝","四公里","南湖","海峡路","谢家湾"]
    }
  ],
  "transfers": [
    {"station": "沙坪坝", "lines": ["1","9","环线"]},
    {"station": "两路口", "lines": ["1","3"]},
    {"station": "牛角沱", "lines": ["2","3"]},
    {"station": "大坪", "lines": ["1","2"]},
    {"station": "杨家坪", "lines": ["2","18"]},
    {"station": "小什字", "lines": ["1","6"]},
    {"station": "红土地", "lines": ["6","10"]},
    {"station": "重庆北站南广场", "lines": ["3","10","环线"]},
    {"station": "五里店", "lines": ["6","9","环线"]},
    {"station": "冉家坝", "lines": ["5","6","环线"]},
    {"station": "石桥铺", "lines": ["1","5","环线"]},
    {"station": "谢家湾", "lines": ["2","环线"]},
    {"station": "四公里", "lines": ["3","环线"]},
    {"station": "富华路", "lines": ["9","18"]},
    {"station": "跳磴", "lines": ["5","18"]}
  ],
  "features": ["穿楼", "跨江", "单轨", "山地起伏", "8D魔幻", "换乘之王"]
}
```

### 池3-2：东京Metro全网

13条线，290+站，日均客流量全球顶级。

```json
{
  "name": "东京Metro+都营",
  "city": "东京",
  "difficulty": "★★★",
  "duration": 720,
  "target_score": 6000,
  "lines": [
    {"id": "G", "name": "银座线", "color": "#FFA500", "stations": ["涩谷","表参道","外苑前","青山一丁目","赤坂见附","溜池山王","虎之门","新桥","银座","京桥","日本桥","三越前","神田","末广町","上野广小路","上野","稻荷町","田原町","浅草"]},
    {"id": "M", "name": "丸之内线", "color": "#FF0000", "stations": ["荻洼","南阿佐谷","新高圆寺","东高圆寺","新中野","中野坂上","西新宿","新宿","新宿三丁目","新宿御苑前","四谷三丁目","四谷","赤坂见附","国会议事堂前","霞关","日比谷","银座","东京","大手町","淡路町","御茶之水","本乡三丁目","后乐园","茗荷谷","新大冢","池袋"]},
    {"id": "H", "name": "日比谷线", "color": "#808080", "stations": ["中目黑","惠比寿","广尾","六本木","神谷町","虎之门Hills","霞关","日比谷","银座","东银座","筑地","八丁堀","茅场町","人形町","小传马町","秋叶原","仲御徒町","上野","入谷","三之轮","南千住","北千住"]},
    {"id": "T", "name": "东西线", "color": "#00CED1", "stations": ["中野","落合","高田马场","早稻田","神乐坂","饭田桥","九段下","竹桥","大手町","日本桥","茅场町","门前仲町","木场","东阳町","南砂町","西葛西","葛西","浦安","南行德","行德","妙典","原木中山","西船桥"]},
    {"id": "C", "name": "千代田线", "color": "#228B22", "stations": ["代代木上原","代代木公园","明治神宫前","表参道","乃木坂","赤坂","国会议事堂前","霞关","日比谷","二重桥前","大手町","新御茶之水","汤岛","根津","千驮木","西日暮里","町屋","北千住","绫濑","北绫濑"]},
    {"id": "Y", "name": "有乐町线", "color": "#FFD700", "stations": ["和光市","地下铁成增","地下铁赤冢","平和台","冰川台","小竹向原","千川","要町","池袋","东池袋","护国寺","江户川桥","饭田桥","市谷","麹町","永田町","樱田门","有乐町","银座一丁目","新富町","月岛","丰洲","辰巳","新木场"]},
    {"id": "Z", "name": "半藏门线", "color": "#9370DB", "stations": ["涩谷","表参道","青山一丁目","永田町","半藏门","九段下","神保町","大手町","三越前","水天宫前","清澄白河","住吉","锦糸町","押上"]},
    {"id": "N", "name": "南北线", "color": "#00CED1", "stations": ["目黑","白金台","白金高轮","麻布十番","六本木一丁目","溜池山王","永田町","半藏门","麹町","市谷","饭田桥","后乐园","东大前","本驹込","驹込","西原","王子","王子神谷","志茂","赤羽岩渊"]},
    {"id": "F", "name": "副都心线", "color": "#8B4513", "stations": ["和光市","地下铁成增","地下铁赤冢","平和台","冰川台","小竹向原","千川","要町","池袋","杂司谷","西早稻田","东新宿","新宿三丁目","北参道","明治神宫前","涩谷"]},
    {"id": "A", "name": "浅草线", "color": "#FF69B4", "stations": ["西马込","马込","中延","户越","五反田","高轮台","泉岳寺","三田","大门","新桥","东银座","宝町","日本桥","人形町","浅草桥","藏前","浅草","本所吾妻桥","押上"]},
    {"id": "I", "name": "三田线", "color": "#0000FF", "stations": ["目黑","白金台","白金高轮","三田","芝公园","御成门","神保町","大手町","日比谷","内幸町","巢鸭","千石","白山","板桥本町","志村坂上","志村三丁目","莲根","西台","高岛平"]},
    {"id": "S", "name": "新宿线", "color": "#00FF00", "stations": ["新宿","新宿三丁目","曙桥","市谷","九段下","神保町","小川町","岩本町","秋叶原","浅草桥","马喰横山","森下","菊川","住吉","西大岛","大岛","东大岛","船堀","一之江","瑞江","篠崎","本八幡"]},
    {"id": "E", "name": "大江户线", "color": "#FF1493", "stations": ["都厅前","新宿西口","东新宿","若松河田","牛込柳町","牛込神乐坂","饭田桥","春日","本乡三丁目","上野御徒町","新御徒町","藏前","两国","森下","清澄白河","门仲","月岛","胜哄","筑地市场","汐留","大门","赤羽桥","麻布十番","六本木","青山一丁目","国立竞技场","代代木","新宿"]}
  ],
  "transfers": [
    {"station": "涩谷", "lines": ["G","Z","F"]},
    {"station": "新宿", "lines": ["M","S","E"]},
    {"station": "池袋", "lines": ["M","Y","F"]},
    {"station": "大手町", "lines": ["M","T","C","Z","I"]},
    {"station": "银座", "lines": ["G","M","H"]},
    {"station": "上野", "lines": ["G","H"]},
    {"station": "秋叶原", "lines": ["H","S"]},
    {"station": "饭田桥", "lines": ["T","Y","N","E"]},
    {"station": "永田町", "lines": ["Y","Z","N"]},
    {"station": "表参道", "lines": ["G","C","Z"]},
    {"station": "赤坂见附", "lines": ["G","M"]},
    {"station": "日比谷", "lines": ["H","C","I"]},
    {"station": "霞关", "lines": ["M","H","C"]},
    {"station": "新桥", "lines": ["G","A"]},
    {"station": "日本桥", "lines": ["G","T","A"]},
    {"station": "神保町", "lines": ["Z","I","S"]},
    {"station": "九段下", "lines": ["T","Z","S"]},
    {"station": "市谷", "lines": ["Y","N","S"]},
    {"station": "三田", "lines": ["A","I"]},
    {"station": "大门", "lines": ["A","E"]},
    {"station": "月岛", "lines": ["Y","E"]},
    {"station": "清澄白河", "lines": ["Z","E"]},
    {"station": "住吉", "lines": ["Z","S"]},
    {"station": "押上", "lines": ["Z","A"]},
    {"station": "白金高轮", "lines": ["N","I"]},
    {"station": "白金台", "lines": ["N","I"]},
    {"station": "目黑", "lines": ["N","I"]},
    {"station": "新宿三丁目", "lines": ["M","F","S"]},
    {"station": "明治神宫前", "lines": ["C","F"]},
    {"station": "青山一丁目", "lines": ["G","Z","E"]},
    {"station": "六本木", "lines": ["H","E"]},
    {"station": "麻布十番", "lines": ["N","E"]},
    {"station": "上野御徒町", "lines": ["E"]},
    {"station": "两国", "lines": ["E"]},
    {"station": "森下", "lines": ["S","E"]}
  ],
  "features": ["全球最密", "山手环线", "换乘迷宫", "早晚高峰极限", "新宿站"]
}
```

### 池3-3：伦敦Underground全网

11条线，270+站，世界最古老地铁。

```json
{
  "name": "伦敦Underground",
  "city": "伦敦",
  "difficulty": "★★★",
  "duration": 720,
  "target_score": 6000,
  "lines": [
    {"id": "Bakerloo", "name": "Bakerloo线", "color": "#B36305", "stations": ["Harrow & Wealdstone","Kenton","South Kenton","North Wembley","Wembley Central","Stonebridge Park","Harlesden","Willesden Junction","Kensal Green","Queen's Park","Kilburn Park","Maida Vale","Warwick Avenue","Paddington","Edgware Road","Marylebone","Baker Street","Regent's Park","Oxford Circus","Piccadilly Circus","Charing Cross","Embankment","Waterloo","Lambeth North","Elephant & Castle"]},
    {"id": "Central", "name": "Central线", "color": "#E32017", "stations": ["West Ruislip","Ruislip Gardens","South Ruislip","Northolt","Greenford","Perivale","Hanger Lane","North Acton","East Acton","White City","Shepherd's Bush","Holland Park","Notting Hill Gate","Queensway","Lancaster Gate","Marble Arch","Bond Street","Oxford Circus","Tottenham Court Road","Holborn","Chancery Lane","St Paul's","Bank","Liverpool Street","Bethnal Green","Mile End","Stratford","Leyton","Leytonstone","Wanstead","Redbridge","Gants Hill","Newbury Park","Barkingside","Fairlop","Hainault","Grange Hill","Chigwell","Roding Valley","Snaresbrook","South Woodford","Woodford","Buckhurst Hill","Loughton","Debden","Theydon Bois","Epping"]},
    {"id": "Circle", "name": "Circle线", "color": "#FFD300", "stations": ["Hammersmith","Goldhawk Road","Shepherd's Bush Market","Wood Lane","Latimer Road","Ladbroke Grove","Westbourne Park","Royal Oak","Paddington","Edgware Road","Baker Street","Great Portland Street","Euston Square","King's Cross St Pancras","Farringdon","Barbican","Moorgate","Liverpool Street","Aldgate","Tower Hill","Monument","Bank","Mansion House","Cannon Street","Temple","Embankment","Westminster","St James's Park","Victoria","Sloane Square","South Kensington","Gloucester Road","High Street Kensington","Notting Hill Gate","Bayswater","Paddington"]},
    {"id": "District", "name": "District线", "color": "#00782A", "stations": ["Upminster","Upminster Bridge","Hornchurch","Elm Park","Dagenham East","Dagenham Heathway","Becontree","Upney","Barking","East Ham","Upton Park","Plaistow","West Ham","Bromley-by-Bow","Bow Road","Mile End","Stepney Green","Whitechapel","Aldgate East","Tower Hill","Monument","Cannon Street","Mansion House","Blackfriars","Temple","Embankment","Westminster","St James's Park","Victoria","Sloane Square","South Kensington","Gloucester Road","Earl's Court","West Kensington","Barons Court","Hammersmith","Ravenscourt Park","Stamford Brook","Turnham Green","Chiswick Park","Acton Town","Ealing Common","Ealing Broadway"]},
    {"id": "Hammersmith & City", "name": "H&C线", "color": "#F3A9BB", "stations": ["Hammersmith","Goldhawk Road","Shepherd's Bush Market","Wood Lane","Latimer Road","Ladbroke Grove","Westbourne Park","Royal Oak","Paddington","Edgware Road","Baker Street","Great Portland Street","Euston Square","King's Cross St Pancras","Farringdon","Barbican","Moorgate","Liverpool Street","Aldgate East","Whitechapel","Stepney Green","Mile End","Bow Road","Bromley-by-Bow","West Ham","Plaistow","Upton Park","East Ham","Barking"]},
    {"id": "Jubilee", "name": "Jubilee线", "color": "#A0A5A9", "stations": ["Stanmore","Canons Park","Queensbury","Kingsbury","Wembley Park","Neasden","Dollis Hill","Willesden Green","Kilburn","West Hampstead","Finchley Road","Swiss Cottage","St John's Wood","Baker Street","Bond Street","Green Park","Westminster","Waterloo","Southwark","London Bridge","Bermondsey","Canada Water","Canary Wharf","North Greenwich","Canning Town","West Ham","Stratford"]},
    {"id": "Metropolitan", "name": "Metropolitan线", "color": "#9B0056", "stations": ["Amersham","Chalfont & Latimer","Chorleywood","Rickmansworth","Croxley","Watford","Moor Park","Northwood","Northwood Hills","Pinner","North Harrow","Harrow-on-the-Hill","Northwick Park","Preston Road","Wembley Park","Finchley Road","Baker Street","Great Portland Street","Euston Square","King's Cross St Pancras","Farringdon","Barbican","Moorgate","Liverpool Street","Aldgate"]},
    {"id": "Northern", "name": "Northern线", "color": "#000000", "stations": ["Edgware","Burnt Oak","Colindale","Hendon Central","Brent Cross","Golders Green","Hampstead","Belsize Park","Chalk Farm","Camden Town","Mornington Crescent","Euston","King's Cross St Pancras","Angel","Old Street","Moorgate","Bank","London Bridge","Borough","Elephant & Castle","Kennington","Oval","Stockwell","Clapham North","Clapham Common","Clapham South","Balham","Tooting Bec","Tooting Broadway","Colliers Wood","South Wimbledon","Morden"]},
    {"id": "Piccadilly", "name": "Piccadilly线", "color": "#003688", "stations": ["Cockfosters","Oakwood","Southgate","Arnos Grove","Bounds Green","Wood Green","Turnpike Lane","Manor House","Finsbury Park","Arsenal","Holloway Road","Caledonian Road","King's Cross St Pancras","Russell Square","Holborn","Covent Garden","Leicester Square","Piccadilly Circus","Green Park","Hyde Park Corner","Knightsbridge","South Kensington","Gloucester Road","Earl's Court","Barons Court","Hammersmith","Ravenscourt Park","Stamford Brook","Turnham Green","Acton Town","Ealing Common","North Ealing","Park Royal","Alperton","Sudbury Town","Sudbury Hill","South Harrow","Rayners Lane","Eastcote","Ruislip Manor","Ruislip","Ickenham","Hillingdon","Uxbridge","Hounslow West","Hounslow Central","Hounslow East","Osterley","Boston Manor","Northfields","South Ealing","Acton Town","Heathrow Terminal 5","Heathrow Terminals 2 & 3","Hatton Cross","Heathrow Terminal 4"]},
    {"id": "Victoria", "name": "Victoria线", "color": "#0098D4", "stations": ["Brixton","Stockwell","Vauxhall","Pimlico","Victoria","Green Park","Oxford Circus","Warren Street","Euston","King's Cross St Pancras","Highbury & Islington","Finsbury Park","Seven Sisters","Tottenham Hale","Blackhorse Road","Walthamstow Central"]},
    {"id": "Waterloo & City", "name": "Waterloo & City线", "color": "#95CDBA", "stations": ["Waterloo","Bank"]}
  ],
  "transfers": [
    {"station": "Baker Street", "lines": ["Bakerloo","Circle","Hammersmith & City","Jubilee","Metropolitan"]},
    {"station": "King's Cross St Pancras", "lines": ["Circle","Hammersmith & City","Metropolitan","Northern","Piccadilly","Victoria"]},
    {"station": "Liverpool Street", "lines": ["Central","Circle","Hammersmith & City","Metropolitan"]},
    {"station": "Bank", "lines": ["Central","Circle","District","Northern","Waterloo & City"]},
    {"station": "Oxford Circus", "lines": ["Bakerloo","Central","Victoria"]},
    {"station": "Green Park", "lines": ["Jubilee","Piccadilly","Victoria"]},
    {"station": "Victoria", "lines": ["Circle","District","Victoria"]},
    {"station": "Waterloo", "lines": ["Bakerloo","Jubilee","Northern","Waterloo & City"]},
    {"station": "London Bridge", "lines": ["Jubilee","Northern"]},
    {"station": "Embankment", "lines": ["Bakerloo","Circle","District","Northern"]},
    {"station": "Euston", "lines": ["Northern","Victoria"]},
    {"station": "Paddington", "lines": ["Bakerloo","Circle","District","Hammersmith & City"]},
    {"station": "Earl's Court", "lines": ["District","Piccadilly"]},
    {"station": "Gloucester Road", "lines": ["Circle","District","Piccadilly"]},
    {"station": "South Kensington", "lines": ["Circle","District","Piccadilly"]},
    {"station": "Notting Hill Gate", "lines": ["Central","Circle","District"]},
    {"station": "Bond Street", "lines": ["Central","Jubilee"]},
    {"station": "Westminster", "lines": ["Circle","District","Jubilee"]},
    {"station": "Canning Town", "lines": ["Jubilee"]},
    {"station": "West Ham", "lines": ["District","Hammersmith & City","Jubilee"]},
    {"station": "Mile End", "lines": ["Central","District","Hammersmith & City"]},
    {"station": "Aldgate East", "lines": ["District","Hammersmith & City"]},
    {"station": "Aldgate", "lines": ["Circle","Metropolitan"]},
    {"station": "Monument", "lines": ["Circle","District"]},
    {"station": "Tower Hill", "lines": ["Circle","District"]},
    {"station": "Moorgate", "lines": ["Circle","Hammersmith & City","Metropolitan","Northern"]},
    {"station": "Barbican", "lines": ["Circle","Hammersmith & City","Metropolitan"]},
    {"station": "Farringdon", "lines": ["Circle","Hammersmith & City","Metropolitan"]},
    {"station": "Euston Square", "lines": ["Circle","Hammersmith & City","Metropolitan"]},
    {"station": "Great Portland Street", "lines": ["Circle","Hammersmith & City","Metropolitan"]},
    {"station": "Edgware Road", "lines": ["Bakerloo","Circle","District","Hammersmith & City"]},
    {"station": "Hammersmith", "lines": ["Circle","District","Hammersmith & City","Piccadilly"]},
    {"station": "Acton Town", "lines": ["District","Piccadilly"]},
    {"station": "Finsbury Park", "lines": ["Piccadilly","Victoria"]},
    {"station": "Highbury & Islington", "lines": ["Victoria"]},
    {"station": "Stockwell", "lines": ["Northern","Victoria"]},
    {"station": "Elephant & Castle", "lines": ["Bakerloo","Northern"]},
    {"station": "Waterloo", "lines": ["Bakerloo","Jubilee","Northern","Waterloo & City"]}
  ],
  "features": ["世界最古老", "环线", "多线交汇", "历史线路", "伦敦塔桥"]
}
```

### 池3-4：巴黎Métro全网

16条线，300+站，密集换乘。

```json
{
  "name": "巴黎Métro",
  "city": "巴黎",
  "difficulty": "★★★",
  "duration": 720,
  "target_score": 6000,
  "lines": [
    {"id": "1", "name": "1号线", "color": "#FFCD00", "stations": ["La Défense","Esplanade de La Défense","Pont de Neuilly","Les Sablons","Porte Maillot","Argentine","Charles de Gaulle-Étoile","George V","Franklin D. Roosevelt","Champs-Élysées-Clemenceau","Concorde","Tuileries","Palais Royal-Musée du Louvre","Louvre-Rivoli","Châtelet","Hôtel de Ville","Saint-Paul","Bastille","Gare de Lyon","Reuilly-Diderot","Nation","Porte de Vincennes","Saint-Mandé","Bérault","Château de Vincennes"]},
    {"id": "4", "name": "4号线", "color": "#CF009E", "stations": ["Porte de Clignancourt","Simplon","Marcadet-Poissonniers","Château Rouge","Gare du Nord","Gare de l'Est","Château d'Eau","Strasbourg-Saint-Denis","Réaumur-Sébastopol","Étienne Marcel","Les Halles","Châtelet","Cité","Saint-Michel","Odéon","Saint-Germain-des-Prés","Saint-Sulpice","Saint-Placide","Montparnasse-Bienvenüe","Vavin","Raspail","Denfert-Rochereau","Mouton-Duvernet","Alésia","Porte d'Orléans","Mairie de Montrouge","Barbara","Bagneux-Lucie Aubrac"]},
    {"id": "6", "name": "6号线", "color": "#6ECA97", "stations": ["Charles de Gaulle-Étoile","Kléber","Boissière","Trocadéro","Passy","Bir-Hakeim","Dupleix","La Motte-Picquet-Grenelle","Cambronne","Sèvres-Lecourbe","Pasteur","Montparnasse-Bienvenüe","Edgar Quinet","Raspail","Denfert-Rochereau","Saint-Jacques","Glacière","Corvisart","Place d'Italie","Nationale","Chevaleret","Quai de la Gare","Bercy","Dugommier","Daumesnil","Bel-Air","Picpus","Nation"]},
    {"id": "8", "name": "8号线", "color": "#E19BDF", "stations": ["Balard","Lourmel","Boucicaut","Félix Faure","Commerce","La Motte-Picquet-Grenelle","École Militaire","La Tour-Maubourg","Invalides","Concorde","Madeleine","Opéra","Richelieu-Drouot","Grands Boulevards","Bonne Nouvelle","Strasbourg-Saint-Denis","République","Filles du Calvaire","Saint-Sébastien-Froissart","Chemin Vert","Bastille","Ledru-Rollin","Faidherbe-Chaligny","Reuilly-Diderot","Montgallet","Daumesnil","Michel Bizot","Porte Dorée","Porte de Charenton","Liberté","Charenton-Écoles","École Vétérinaire de Maisons-Alfort","Maisons-Alfort-Stade","Maisons-Alfort-Les Juilliottes","Créteil-L'Échat","Créteil-Université","Créteil-Préfecture","Pointe du Lac"]},
    {"id": "9", "name": "9号线", "color": "#B6BD00", "stations": ["Pont de Sèvres","Billancourt","Marcel Sembat","Porte de Saint-Cloud","Exelmans","Michel-Ange-Molitor","Michel-Ange-Auteuil","Jasmin","Ranelagh","La Muette","Rue de la Pompe","Trocadéro","Iéna","Alma-Marceau","Franklin D. Roosevelt","Saint-Philippe-du-Roule","Miromesnil","Saint-Augustin","Havre-Caumartin","Chaussée d'Antin-La Fayette","Opéra","Richelieu-Drouot","Grands Boulevards","Bonne Nouvelle","Strasbourg-Saint-Denis","République","Oberkampf","Saint-Ambroise","Voltaire","Charonne","Rue des Boulets","Nation","Buzenval","Maraîchers","Porte de Montreuil","Robespierre","Croix de Chavaux","Mairie de Montreuil"]},
    {"id": "14", "name": "14号线", "color": "#662483", "stations": ["Mairie de Saint-Ouen","Saint-Ouen","Porte de Clichy","Pont Cardinet","Saint-Lazare","Madeleine","Pyramides","Châtelet","Gare de Lyon","Bercy","Cour Saint-Émilion","Bibliothèque François Mitterrand","Olympiades","Maison Blanche","Hôpital Bicêtre","Villejuif-Gustave Roussy","L'Haÿ-les-Roses","Chevilly-Larue","Thiais-Orly","Aéroport d'Orly"]},
    {"id": "13", "name": "13号线", "color": "#6EC4E8", "stations": ["Asnières-Gennevilliers-Les Courtilles","Les Agnettes","Gabriel Péri","Mairie de Clichy","Porte de Clichy","Brochant","La Fourche","Guy Môquet","Porte de Saint-Ouen","La Fourche","Place de Clichy","Liège","Saint-Lazare","Champs-Élysées-Clemenceau","Invalides","Varenne","Saint-François-Xavier","Duroc","Montparnasse-Bienvenüe","Gaîté","Pernety","Plaisance","Porte de Vanves","Malakoff-Plateau de Vanves","Malakoff-Rue Étienne Dolet","Châtillon-Montrouge"]}
  ],
  "transfers": [
    {"station": "Châtelet", "lines": ["1","4","14"]},
    {"station": "Charles de Gaulle-Étoile", "lines": ["1","6"]},
    {"station": "Nation", "lines": ["1","6","9"]},
    {"station": "Bastille", "lines": ["1","8"]},
    {"station": "Gare de Lyon", "lines": ["1","14"]},
    {"station": "Montparnasse-Bienvenüe", "lines": ["4","6","13"]},
    {"station": "Denfert-Rochereau", "lines": ["4","6"]},
    {"station": "Raspail", "lines": ["4","6"]},
    {"station": "Strasbourg-Saint-Denis", "lines": ["4","8","9"]},
    {"station": "République", "lines": ["8","9"]},
    {"station": "Opéra", "lines": ["8","9"]},
    {"station": "Madeleine", "lines": ["8","14"]},
    {"station": "Concorde", "lines": ["1","8"]},
    {"station": "Franklin D. Roosevelt", "lines": ["1","9"]},
    {"station": "Trocadéro", "lines": ["6","9"]},
    {"station": "La Motte-Picquet-Grenelle", "lines": ["6","8"]},
    {"station": "Daumesnil", "lines": ["6","8"]},
    {"station": "Reuilly-Diderot", "lines": ["1","8"]},
    {"station": "Saint-Lazare", "lines": ["14","13"]},
    {"station": "Porte de Clichy", "lines": ["14","13"]},
    {"station": "Bercy", "lines": ["6","14"]},
    {"station": "Invalides", "lines": ["8","13"]},
    {"station": "Duroc", "lines": ["13"]},
    {"station": "Richelieu-Drouot", "lines": ["8","9"]},
    {"station": "Grands Boulevards", "lines": ["8","9"]},
    {"station": "Bonne Nouvelle", "lines": ["8","9"]}
  ],
  "features": ["密集换乘", "塞纳河", "历史中心", "艺术地铁", "新艺术风格"]
}
```

## 无限模式（∞）：以成都为基础

### 池4-1：成都地铁全线（基础）

截至2026年9月，成都地铁共开通17条线路（不含有轨电车），线路总长718.95千米，共计452座车站投入运营，其中换乘站80座。2025年12月31日单日客运量创新纪录达1003.09万人次。

```json
{
  "name": "成都地铁全网",
  "city": "成都",
  "difficulty": "∞",
  "duration": 0,
  "target_score": 0,
  "lines": [
    {"id": "1", "name": "1号线", "color": "#0000FF", "stations": ["韦家碾","升仙湖","火车北站","人民北路","文殊院","骡马市","天府广场","锦江宾馆","华西坝","省体育馆","倪家桥","桐梓林","火车南站","高新","金融城","孵化园","锦城广场","世纪城","天府三街","天府五街","华府大道","四河","广都","五根松","红石公园","麓湖","武汉路","天府公园","西博城","广州路","兴隆湖","科学城"]},
    {"id": "2", "name": "2号线", "color": "#FF8C00", "stations": ["犀浦","天河路","百草路","金周路","金科北路","迎宾大道","茶店子客运站","羊犀立交","一品天下","蜀汉路东","白果林","中医大省医院","通惠门","人民公园","天府广场","春熙路","东门大桥","牛王庙","牛市口","东大路","塔子山公园","成都行政学院","大面铺","连山坡","界牌","书房","龙平路","龙泉驿","大面铺"]},
    {"id": "3", "name": "3号线", "color": "#FF69B4", "stations": ["成都医学院","石油大学","钟楼","马超西路","团结新区","锦水河","三河场","金华寺东路","植物园","军区总医院","熊猫大道","动物园","昭觉寺南路","驷马桥","李家沱","前锋路","红星桥","市二医院","春熙路","新南门","磨子桥","省体育馆","高升桥","红牌楼","太平园","川藏立交","武侯立交","武青南路","双凤桥","龙桥路","航都大街","迎春桥","东升","双流广场","三里坝","双流西站"]},
    {"id": "4", "name": "4号线", "color": "#00CED1", "stations": ["万盛","凤溪河","杨柳河","非遗博览园","蔡桥","中坝","成都西站","清江西路","文化宫","西南财大","草堂北路","中医大省医院","宽窄巷子","骡马市","太升南路","市二医院","玉双路","双桥路","万年场","槐树店","来龙","十陵","成都大学","明蜀王陵","西河"]},
    {"id": "5", "name": "5号线", "color": "#9370DB", "stations": ["华桂路","柏水场","廖家湾","北部商贸城","幸福桥","九道堰","杜家碾","大丰","石犀公园","皇花园","陆家桥","泉水路","洞子口","福宁路","五块石","西北桥","花牌坊","抚琴","中医大省医院","青羊宫","省骨科医院","高升桥","科园","九兴大道","神仙树","石羊立交","市一医院","交子大道","锦城大道","大源","民乐","骑龙","警官学院","二江寺","南湖立交","怡心湖","龙马路","回龙"]},
    {"id": "6", "name": "6号线", "color": "#8B4513", "stations": ["望丛祠","和平街","郫筒","蜀新大道","檬梓","尚锦路","红高路","天宇路","兴业北街","交大犀浦","侯家桥","兴盛","青杠","西华大道","金府","星河","西南交大","沙湾","西北桥","人民北路","梁家巷","前锋路","建设北路","新鸿路","玉双路","牛王庙","东光","琉璃场","琉三路","金石路","金融城东","中和","张家寺","陆肖","观东","新通大道","新川路","龙灯山","蒲草塘","万安","麓山大道","沈阳路","青岛路","昌公堰","杭州路","天府商务区","西博城","秦皇寺","松林","芦角","钓鱼嘴","回龙"]},
    {"id": "7", "name": "7号线", "color": "#FFD700", "stations": ["火车北站","驷马桥","八里庄","二仙桥","理工大学","崔家店","双店路","槐树店","迎晖路","成都东客站","大观","狮子山","四川师大","琉璃场","三瓦窑","火车南站","神仙树","高朋大道","太平园","龙爪堰","武侯大道","文化宫","东坡路","一品天下","茶店子","花照壁","西南交大","九里堤","火车北站"]},
    {"id": "8", "name": "8号线", "color": "#90EE90", "stations": ["十里店","理工大学","杉板桥","万年路","双桥路","玉双路","东郊记忆","杉板桥","莲花","东光","净居寺","川大望江校区","东湖公园","倪家桥","芳草街","永丰","九兴大道","石羊立交","三元","高朋大道","殷家林","庆安","石羊","顺风","珠江路","川大江安校区","文星","莲花"]},
    {"id": "9", "name": "9号线", "color": "#FF4500", "stations": ["黄田坝","成都西站","培风","机投桥","武青南路","簇桥","华兴","太平寺","三元","金融城东","心岛","孵化园","锦城大道","三元","黄田坝"]},
    {"id": "10", "name": "10号线", "color": "#00BFFF", "stations": ["太平园","簇锦","华兴","金花","双流机场1航站楼","双流机场2航站楼","双流西站","应天寺","黄水","板桥","花源","新津站","花桥","五津","儒林路","刘家碾","新平"]},
    {"id": "17", "name": "17号线", "color": "#87CEEB", "stations": ["九江北","白佛桥","机投桥","阳公桥","清水河大桥","龙爪堰","浣花里","省骨科医院","小南街","人民公园","西大街","城隍庙","红星桥","建设北路","踏水桥","二仙桥","机车厂","航天路","威灵","高洪"]},
    {"id": "18", "name": "18号线", "color": "#008B8B", "stations": ["火车南站","孵化园","锦城广场东","世纪城","海昌路","西博城","兴隆","天府新站","三岔","福田","天府机场北","天府机场1号2号航站楼","天府机场3号4号航站楼"]},
    {"id": "19", "name": "19号线", "color": "#FF1493", "stations": ["金星","黄石","市五医院","凤溪河","温泉大道","明光","九江北","龙桥路","双流机场2航站楼东","龙港","温家山","牧华路","怡心湖","正兴湾","红莲","天府商务区","蓝家店","天府新站","合江","天府机场北"]}
  ],
  "transfers": [
    {"station": "天府广场", "lines": ["1","2"]},
    {"station": "春熙路", "lines": ["2","3"]},
    {"station": "省体育馆", "lines": ["1","3"]},
    {"station": "骡马市", "lines": ["1","4"]},
    {"station": "中医大省医院", "lines": ["2","4","5"]},
    {"station": "市二医院", "lines": ["3","4"]},
    {"station": "玉双路", "lines": ["4","6","8"]},
    {"station": "牛王庙", "lines": ["2","6"]},
    {"station": "西北桥", "lines": ["5","6"]},
    {"station": "前锋路", "lines": ["3","6"]},
    {"station": "建设北路", "lines": ["6","17"]},
    {"station": "红星桥", "lines": ["3","17"]},
    {"station": "人民北路", "lines": ["1","6"]},
    {"station": "火车北站", "lines": ["1","7"]},
    {"station": "驷马桥", "lines": ["3","7"]},
    {"station": "槐树店", "lines": ["4","7"]},
    {"station": "成都东客站", "lines": ["2","7"]},
    {"station": "琉璃场", "lines": ["6","7"]},
    {"station": "火车南站", "lines": ["1","7","18"]},
    {"station": "神仙树", "lines": ["5","7"]},
    {"station": "太平园", "lines": ["3","7","10"]},
    {"station": "文化宫", "lines": ["4","7"]},
    {"station": "一品天下", "lines": ["2","7"]},
    {"station": "西南交大", "lines": ["6","7"]},
    {"station": "高升桥", "lines": ["3","5"]},
    {"station": "红牌楼", "lines": ["3"]},
    {"station": "倪家桥", "lines": ["1","8"]},
    {"station": "东光", "lines": ["6","8"]},
    {"station": "净居寺", "lines": ["8"]},
    {"station": "东湖公园", "lines": ["8"]},
    {"station": "高朋大道", "lines": ["7","8"]},
    {"station": "九兴大道", "lines": ["5","8"]},
    {"station": "石羊立交", "lines": ["5","8"]},
    {"station": "三元", "lines": ["8","9"]},
    {"station": "金融城东", "lines": ["6","9"]},
    {"station": "孵化园", "lines": ["1","9","18"]},
    {"station": "锦城大道", "lines": ["5","9"]},
    {"station": "华兴", "lines": ["9","10"]},
    {"station": "簇桥", "lines": ["9","10"]},
    {"station": "双流西站", "lines": ["3","10"]},
    {"station": "龙桥路", "lines": ["3","19"]},
    {"station": "九江北", "lines": ["17","19"]},
    {"station": "机投桥", "lines": ["9","17"]},
    {"station": "龙爪堰", "lines": ["7","17"]},
    {"station": "省骨科医院", "lines": ["5","17"]},
    {"station": "西博城", "lines": ["1","6","18"]},
    {"station": "天府新站", "lines": ["18","19"]},
    {"station": "天府机场北", "lines": ["18","19"]},
    {"station": "双流机场2航站楼", "lines": ["10","19"]},
    {"station": "怡心湖", "lines": ["5","19"]},
    {"station": "天府商务区", "lines": ["6","19"]}
  ],
  "features": ["环线+放射", "机场线", "大运村", "熊猫基地", "春熙路", "天府广场", "无限模式基础"]
}
```

### 池4-2：成都+重庆跨城组合

从成都和重庆各抽2—3条线，形成跨城换乘网络。

```json
{
  "name": "成渝跨城组合",
  "city": "成都+重庆",
  "difficulty": "∞",
  "duration": 0,
  "target_score": 0,
  "lines": [
    {"id": "CD-1", "name": "成都1号线", "color": "#0000FF", "stations": ["韦家碾","升仙湖","火车北站","人民北路","文殊院","骡马市","天府广场","锦江宾馆","华西坝","省体育馆","倪家桥","桐梓林","火车南站","高新","金融城","孵化园","锦城广场","世纪城","天府三街","天府五街","华府大道","四河","广都"]},
    {"id": "CD-7", "name": "成都7号线", "color": "#FFD700", "stations": ["火车北站","驷马桥","八里庄","二仙桥","理工大学","崔家店","双店路","槐树店","迎晖路","成都东客站","大观","狮子山","四川师大","琉璃场","三瓦窑","火车南站","神仙树","高朋大道","太平园","龙爪堰","武侯大道","文化宫","东坡路","一品天下","茶店子","花照壁","西南交大","九里堤","火车北站"]},
    {"id": "CQ-1", "name": "重庆1号线", "color": "#DC143C", "stations": ["朝天门","小什字","较场口","七星岗","两路口","鹅岭","大坪","石油路","歇台子","石桥铺","高庙村","马家岩","小龙坎","沙坪坝","杨公桥","烈士墓","磁器口","石井坡","双碑","赖家桥","微电园","陈家桥","大学城","尖顶坡","璧山"]},
    {"id": "CQ-3", "name": "重庆3号线", "color": "#FFD700", "stations": ["鱼洞","金竹","鱼胡路","学堂湾","大山村","花溪","岔路口","九公里","麒龙","八公里","二塘","六公里","五公里","四公里","南坪","工贸","铜元局","两路口","牛角沱","华新街","观音桥","红旗河沟","嘉州路","郑家院子","唐家院子","狮子坪","重庆北站南广场","重庆北站北广场","童家院子","翠云","园博园","鸳鸯","金渝","金童路","回兴","双龙","碧津","江北机场T2航站楼","举人坝"]}
  ],
  "transfers": [
    {"station": "火车北站", "lines": ["CD-1","CD-7"]},
    {"station": "火车南站", "lines": ["CD-1","CD-7"]},
    {"station": "两路口", "lines": ["CQ-1","CQ-3"]}
  ],
  "features": ["跨城组合", "成渝双城", "环线+穿楼", "无限模式扩展"]
}
```

### 池4-3：随机程序化生成

从真实线网中随机抽取线路组合，每局不同。

```json
{
  "name": "随机组合线网",
  "city": "随机",
  "difficulty": "∞",
  "duration": 0,
  "target_score": 0,
  "lines": [],
  "transfers": [],
  "features": ["程序化生成", "每局不同", "真实线路池", "肉鸽升级"],
  "generation_rules": {
    "start_lines": 2,
    "new_line_interval": 180,
    "max_lines": 12,
    "line_pool": ["温州S1","温州S2","成都1","成都2","成都7","重庆1","重庆2","重庆3","宁波12","都江堰M-TR","香港荃湾","香港观塘","香港港岛","台北淡水信义","台北板南"],
    "transfer_probability": 0.3
  }
}
```

### 池4-4：特色线路混搭

将特色线路单独组合，适合无限模式中作为“主题局”。

```json
{
  "name": "特色线路混搭",
  "city": "特色主题",
  "difficulty": "∞",
  "duration": 0,
  "target_score": 0,
  "lines": [
    {"id": "CQ-2", "name": "重庆2号线（穿楼）", "color": "#228B22", "stations": ["较场口","临江门","黄花园","大溪沟","曾家岩","牛角沱","李子坝","佛图关","大坪","袁家岗","谢家湾","杨家坪","动物园","大堰村","马王场","平安","大渡口","新山村","天堂堡","建桥","金家湾","刘家坝","白居寺","鱼洞"]},
    {"id": "NB-12", "name": "宁波12号线（跨海）", "color": "#00CED1", "stations": ["小洋江","云龙","横溪","塘溪","咸祥","松岙","贤庠","大徐","丹城","大目湾"]},
    {"id": "DJY-MTR", "name": "都江堰M-TR（雪山）", "color": "#2E8B57", "stations": ["青城山高铁站","青城山景区","东软学院","中兴","石厂湾","都江堰景区","南桥","灌县古城","玉垒山","离堆公园","万达主题公园","熊猫谷","八角庙"]},
    {"id": "DL-201", "name": "大连201路（百年电车）", "color": "#FF8C00", "stations": ["海之韵公园","东海公园","寺儿沟","二七广场","三八广场","中山广场","友好广场","青泥洼桥","大连火车站","东关街","北京街","大同街","五一广场","香炉礁","工人村","春柳","沙河口火车站","兴工街"]}
  ],
  "transfers": [
    {"station": "大坪", "lines": ["CQ-2"]},
    {"station": "牛角沱", "lines": ["CQ-2"]}
  ],
  "features": ["穿楼", "跨海", "雪山有轨电车", "百年电车", "主题局"]
}
```
