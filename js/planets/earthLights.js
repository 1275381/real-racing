import * as THREE from 'three';

/*
 * 地球夜景灯光模块（契约见 out/earth-cities-design.md §3/§5；坐标公式 §2.1 唯一公式）
 *   build(deps) -> { map }
 *     deps  = { landAt, radius }   // landAt: (latDeg,lonDeg)=>boolean（earth.js §1 掩码采样）
 *                                  // radius 本模块不用（灯光是纹理，无尺度概念），仅统一签名
 *     map   = THREE.CanvasTexture，1024×512 等距圆柱夜景灯光，SRGBColorSpace，flipY 默认 true
 *             海洋纯黑 rgb(0,0,0)；陆上按「人口潜势场」分档点暗黄光斑 + 1px 级小镇灯珠散点；
 *             城市站点处叠加 2~3 层径向渐变光斑（T1≈5px … T4≈1.5px）
 *   citySites(landAt) -> [ 40 站 { name, country, lat, lon, tier, pop, desc, sigmaDeg } ]
 *     确定性螺旋搜索落位（固定种子、全程无随机数）：名义坐标起、采样步长 0.35°（≈陆地
 *     掩码半像素）、最远 42×0.7°≈30° 首个 landAt===true 落位；40 站落定后按 1.2° 最小
 *     间隔解冲突（冲突者沿「本站−已落站」方向外推 0.7° 重搜，≤3 轮）。
 *     earthCities 唯一导入本导出（单一事实源）→ 灯光与楼严格对位。
 *
 * 坐标约定（§2.1）：像素 (i,j) 中心 → u=(i+0.5)/W，lat=90−180·(j+0.5)/H，lon=360·u；
 *   经度零点=纹理最左列；uv.y=1=北极。与 earthCities 的 latLonToLocal 同一局部系。
 *
 * 无缝策略：值噪声晶格沿经度整周期取模（同 earth.js:66-79）；chamfer 距离变换 x 向环绕；
 * 城市光斑按 x±W 三重补画（同 earth.js:356-378 月面陨石坑画法）。
 *
 * 有意偏差（§3.2-5 / §9-5，唯一一处）：城市站点光斑允许向邻近海面渗光（港湾灯光倒影
 * 观感）——若把光斑也乘陆地掩码，海岸城市的光会沿像素边被硬切，观感破碎；
 * 除站点光斑外的一切发光严格陆内，海洋像素本体一律置黑。
 */

/* ========================= 40 座实名城市表（§5；名义坐标 = 搜索种子，非地理断言） ========================= */

/* [名称, 国家, 名义纬度, 名义经度, tier, 人口（信息卡文案）, 一句简介] */
const CITY_TABLE = [
    ['东京', '日本', 35.7, 139.7, 1, '3700万(圈)', '世界最大的都市圈，涩谷一个路口每天通行约 250 万人。'],
    ['德里', '印度', 28.6, 77.2, 1, '3200万(圈)', '新德里与旧德里合抱的首都圈，莫卧儿古城与卫星新城共生。'],
    ['上海', '中国', 31.2, 121.5, 1, '2900万(圈)', '长江口崛起的东方明珠，陆家嘴天际线三十年从农田变成丛林。'],
    ['圣保罗', '巴西', -23.55, -46.6, 1, '2200万(圈)', '南美最大城市，直升机通勤量全球第一的混凝土森林。'],
    ['墨西哥城', '墨西哥', 19.4, -99.1, 1, '2200万(圈)', '建在古湖床上的阿兹特克都城，正以每年约 50cm 缓慢沉降。'],
    ['开罗', '埃及', 30.0, 31.2, 1, '2100万(圈)', '尼罗河畔的千年之城，与吉萨金字塔隔河相望。'],
    ['北京', '中国', 39.9, 116.4, 1, '2100万', '三千年古都，中轴线南起永定门北至钟鼓楼。'],
    ['孟买', '印度', 19.1, 72.9, 1, '2000万', '七座岛屿填合而成的印度金融之都，宝莱坞所在地。'],
    ['纽约', '美国', 40.7, -74.0, 1, '1900万(圈)', '哈德逊河口的世界十字路口，曼哈顿grid规划于1811年。'],
    ['拉各斯', '尼日利亚', 6.5, 3.4, 1, '1500万(圈)', '非洲增长最快的超级城市，潟湖与大西洋之间的狭长岛链。'],
    ['布宜诺斯艾利斯', '阿根廷', -34.6, -58.4, 2, '1500万(圈)', '「南美巴黎」，探戈诞生在博卡区的街角。'],
    ['伊斯坦布尔', '土耳其', 41.0, 28.9, 2, '1500万', '横跨欧亚两洲，博斯普鲁斯海峡穿城而过。'],
    ['马尼拉', '菲律宾', 14.6, 121.0, 2, '1400万(圈)', '西太平洋港口都市，西班牙王城四百年城墙犹在。'],
    ['里约热内卢', '巴西', -22.9, -43.2, 2, '1300万(圈)', '基督像张开双臂俯瞰的海湾之城，沙滩与山体之间挤满楼群。'],
    ['莫斯科', '俄罗斯', 55.8, 37.6, 2, '1250万', '克里姆林宫所在的森林之都，放射状环路如年轮。'],
    ['洛杉矶', '美国', 34.05, -118.2, 2, '1300万(圈)', '天使之城，电影工业让「Hollywood」成为地名以外的词。'],
    ['雅加达', '印度尼西亚', -6.2, 106.8, 2, '1100万(圈)', '赤道圈内的千万之都，全城四成土地低于海平面。'],
    ['曼谷', '泰国', 13.75, 100.5, 2, '1100万(圈)', '湄南河上的天使之城，金色佛塔与高架轻轨同框。'],
    ['巴黎', '法国', 48.9, 2.35, 2, '1100万(圈)', '奥斯曼男爵十九世纪改造的放射状街道模板。'],
    ['首尔', '韩国', 37.6, 127.0, 2, '970万', '汉江穿城的首都，六百年都城与数字霓虹共存。'],
    ['伦敦', '英国', 51.5, -0.13, 2, '900万(圈)', '泰晤士河畔两千年古城，本初子午线在城郊格林尼治。'],
    ['芝加哥', '美国', 41.9, -87.6, 2, '950万(圈)', '现代摩天楼的发源地，密歇根湖畔的风城。'],
    ['利马', '秘鲁', -12.0, -77.0, 2, '1000万', '太平洋悬崖上的沙漠首都，一年不足一指降雨。'],
    ['马德里', '西班牙', 40.4, -3.7, 3, '660万(圈)', '欧洲海拔最高的首都之一，太阳门广场是公路零起点。'],
    ['香港', '中国', 22.3, 114.2, 2, '740万', '维多利亚港两岸密度登峰造极的垂直城市。'],
    ['多伦多', '加拿大', 43.65, -79.4, 3, '620万(圈)', '安大略湖畔的移民之城，一半以上居民出生海外。'],
    ['圣地亚哥', '智利', -33.45, -70.7, 3, '680万(圈)', '安第斯雪山脚下的首都，晴天可从市区直望雪峰。'],
    ['悉尼', '澳大利亚', -33.87, 151.2, 3, '530万(圈)', '杰克逊港的白帆歌剧院，南半球最老的欧洲殖民城。'],
    ['新加坡', '新加坡', 1.35, 103.8, 3, '590万', '赤道线上的花园城市国家，填海造陆仍在生长。'],
    ['迪拜', '阿联酋', 25.2, 55.3, 3, '350万', '沙漠中的垂直实验室，八百米高楼从鱼村旁拔起。'],
    ['柏林', '德国', 52.5, 13.4, 3, '380万', '一堵墙分开又合拢的城市，博物馆岛收藏着整部欧洲史。'],
    ['罗马', '意大利', 41.9, 12.5, 3, '430万', '条条大路通向的永恒之城，地下叠压着两千年地层。'],
    ['旧金山', '美国', 37.77, -122.4, 3, '470万(市)', '半岛山城，金门海峡的红桥是它的名片。'],
    ['内罗毕', '肯尼亚', -1.3, 36.8, 3, '470万', '赤道高原上的绿荫之都，城市围栏外就是草原与狮群。'],
    ['开普敦', '南非', -33.9, 18.4, 3, '460万', '桌山脚下好望角旁，两洋交汇的风暴角之城。'],
    ['温哥华', '加拿大', 49.28, -123.1, 4, '260万(圈)', '雪山与海湾之间的宜居港城，全年可滑雪又可出海。'],
    ['卡萨布兰卡', '摩洛哥', 33.6, -7.6, 4, '380万(圈)', '大西洋畔的白色之城，电影让它永远定格在北非谍影。'],
    ['哈瓦那', '古巴', 23.1, -82.4, 4, '210万', '加勒比海的时光胶囊，五十年代的老爷车仍在滨海大道巡游。'],
    ['奥克兰', '新西兰', -36.85, 174.76, 4, '170万', '五十座死火山锥上的千帆之都。'],
    ['约翰内斯堡', '南非', -26.2, 28.0, 3, '600万(圈)', '金矿脉上长出的黄金之城，非洲的经济发动机。'],
];

/* tier → sigmaDeg（earthCities 楼群高斯散布用，§4.2）/ 站点光斑半径（1024 宽像素，§3.2-5）/ 渐变层数 */
const TIER = {
    1: { sigmaDeg: 0.55, glowR: 5.0, layers: 3 },
    2: { sigmaDeg: 0.42, glowR: 3.5, layers: 3 },
    3: { sigmaDeg: 0.32, glowR: 2.5, layers: 2 },
    4: { sigmaDeg: 0.24, glowR: 1.5, layers: 2 },
};

/* ========================= 随机 / 晶格查表噪声（同 earth.js:21-91 思路，内置副本） ========================= */

function hash2(ix, iy, seed) {
    let h = Math.imul(ix, 0x27d4eb2d) ^ Math.imul(iy, 0x165667b1) ^ Math.imul(seed, 0x9e3779b1);
    h = Math.imul(h ^ (h >>> 15), 0x85ebca6b);
    h ^= h >>> 13;
    h = Math.imul(h, 0xc2b2ae35);
    h ^= h >>> 16;
    return (h >>> 0) / 4294967296;
}

/* 预生成周期值噪声「场」：oct 层晶格，第 i 层宽 px·2^i（经度周期），行覆盖 [yMin,yMax]·2^i
 * 并各外扩一行；采样只做数组读取 + 双线性插值（x 环绕 → 经度无缝） */
function makeField(px, oct, yMin, yMax, seed) {
    const layers = [];
    let p = px, lo = yMin, hi = yMax;
    for (let i = 0; i < oct; i++) {
        const y0 = Math.floor(lo) - 1, y1 = Math.ceil(hi) + 1;
        const h = y1 - y0 + 1;
        const t = new Float32Array(p * h);
        for (let yy = 0; yy < h; yy++) {
            const row = yy * p, ly = yy + y0;
            for (let xx = 0; xx < p; xx++) t[row + xx] = hash2(xx, ly, seed + i * 101);
        }
        layers.push({ t: t, w: p, y0: y0, h: h });
        p *= 2; lo *= 2; hi *= 2;
    }
    let amp = 1, tot = 0;
    const amps = [];
    for (let i = 0; i < oct; i++) { amps.push(amp); tot += amp; amp *= 0.5; }
    return { layers: layers, amps: amps, inv: 1 / tot };
}

/* 单层晶格采样：x 周期取模（无缝核心），y 行钳制防越界 */
function latt(L, x, y) {
    const xi = Math.floor(x), yi = Math.floor(y);
    const xf = x - xi, yf = y - yi;
    const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
    let x0 = xi % L.w;
    if (x0 < 0) x0 += L.w;
    const x1 = x0 + 1 === L.w ? 0 : x0 + 1;
    let r0 = yi - L.y0;
    if (r0 < 0) r0 = 0;
    else if (r0 > L.h - 2) r0 = L.h - 2;
    const b0 = r0 * L.w, b1 = (r0 + 1) * L.w;
    const a = L.t[b0 + x0], b = L.t[b0 + x1], c = L.t[b1 + x0], d = L.t[b1 + x1];
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v;
}

/* 整场求值：分形叠加（2~3 倍频） */
function nsAt(f, x, y) {
    let s = 0;
    for (let i = 0; i < f.layers.length; i++) {
        s += f.amps[i] * latt(f.layers[i], x, y);
        x *= 2; y *= 2;
    }
    return s * f.inv;
}

const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x);

/* JS 版 smoothstep（earth.js:95-98 同款）：支持降序边缘（a>b 即递减斜坡）——CPU 代码，
 * 无 GLSL smoothstep(edge0>edge1) 的未定义行为问题（§3.2-3 复核修订点） */
function smoothstep(a, b, x) {
    const t = clamp01((x - a) / (b - a));
    return t * t * (3 - 2 * t);
}

const mix = (a, b, t) => a + (b - a) * t;
const wrap180 = (x) => ((x % 360) + 540) % 360 - 180;
const cosOf = (latDeg) => Math.max(0.2, Math.cos(latDeg * Math.PI / 180));

function mkCanvas(w, h) {
    const c = document.createElement('canvas');
    c.width = w;
    c.height = h;
    return c;
}

/* ========================= 城市站点落位（确定性螺旋搜索，§5 搜索算法） ========================= */

export function citySites(landAt) {
    const MIN_GAP = 1.2;      // 站间最小间隔（度）== 点击热区角半径下限（§4.2-1）
    const STEP = 0.35;        // 环上采样弧距（度）≈ 陆地掩码半像素
    const RING_STEP = 0.7;    // 相邻搜索环半径差（度）
    const MAX_RING = 42;      // 42×0.7 = 29.4° ≈ 30°（§9-1：约 1/3 陆地密度下必有陆地）
    const MAX_PUSH = 3;       // 解冲突外推重搜轮数上限

    /* 从 (lat0,lon0) 螺旋外搜：环 k 半径 k·0.7°，环上 STEP 等距方位 + 黄金角相位去相关，
     * 首个 landAt===true 即落点；找不到退回名义坐标（兜底，§9-1 岛城观感） */
    function settle(lat0, lon0) {
        if (landAt(lat0, lon0) === true) return { lat: lat0, lon: wrap180(lon0) };
        const cosLat = cosOf(lat0);
        for (let k = 1; k <= MAX_RING; k++) {
            const rk = k * RING_STEP;
            const n = Math.max(8, Math.round(2 * Math.PI * rk / STEP));
            for (let m = 0; m < n; m++) {
                const a = 2 * Math.PI * m / n + k * 2.399963;       // 黄金角相位，确定性
                const lat = lat0 + rk * Math.cos(a);
                if (Math.abs(lat) >= 89) continue;
                const lon = lon0 + rk * Math.sin(a) / cosLat;       // 小圆近似（§4.2-4 同式）
                if (landAt(lat, lon) === true) return { lat: lat, lon: wrap180(lon) };
            }
        }
        return { lat: lat0, lon: wrap180(lon0) };
    }

    /* 站间角距（经度按 cos(midLat) 折算成弧度距） */
    function gap(a, b) {
        const dLon = wrap180(a.lon - b.lon) * cosOf((a.lat + b.lat) * 0.5);
        return Math.hypot(a.lat - b.lat, dLon);
    }

    /* 40 站依表序落位 + 最小间隔解冲突（冲突者沿「本站−已落站」方向外推 0.7° 重搜） */
    const sites = [];
    for (let i = 0; i < CITY_TABLE.length; i++) {
        const row = CITY_TABLE[i];
        let s = settle(row[2], row[3]);
        for (let push = 0; push < MAX_PUSH; push++) {
            let hit = null;
            for (let j = 0; j < sites.length; j++) {
                if (gap(s, sites[j]) < MIN_GAP) { hit = sites[j]; break; }
            }
            if (!hit) break;
            const dLat = s.lat - hit.lat;
            const dLon = wrap180(s.lon - hit.lon) * cosOf(s.lat);
            const len = Math.hypot(dLat, dLon) || 1;
            s = settle(s.lat + 0.7 * dLat / len, s.lon + 0.7 * dLon / len);
        }
        sites.push({
            name: row[0],
            country: row[1],
            lat: s.lat,
            lon: s.lon,
            tier: row[4],
            pop: row[5],
            desc: row[6],
            sigmaDeg: TIER[row[4]].sigmaDeg,
        });
    }
    return sites;
}

/* ========================= 夜景灯光绘制（§3.2 算法，顺序执行） ========================= */

function drawLights(landAt, sites) {
    const W = 1024, H = 512, HW = 512, HH = 256;

    /* ① 陆地网格（半分辨率，chamfer 距离变换用；131k 次 landAt 采样） */
    const grid = new Uint8Array(HW * HH);
    for (let j = 0; j < HH; j++) {
        const lat = 90 - 180 * (j + 0.5) / HH;
        for (let i = 0; i < HW; i++) {
            grid[j * HW + i] = landAt(lat, 360 * (i + 0.5) / HW) === true ? 1 : 0;
        }
    }

    /* ② 海岸距离：3-4 权重两遍 chamfer 距离变换（正向左上→右下、反向右下→左上，
     * x 向环绕保证跨缝陆地距离连续）→ 每陆格到海岸的近似格距 */
    const INF = 1e9;
    const dist = new Float32Array(HW * HH);
    for (let q = 0; q < dist.length; q++) dist[q] = grid[q] ? INF : 0;
    const D1 = 3, D2 = 4;                                   // 正交 / 对角权重
    for (let j = 0; j < HH; j++) {                          // 正向
        for (let i = 0; i < HW; i++) {
            const q = j * HW + i;
            if (dist[q] === 0) continue;
            let d = dist[j * HW + (i + HW - 1) % HW] + D1;
            if (j > 0) {
                const up = (j - 1) * HW;
                if (dist[up + i] + D1 < d) d = dist[up + i] + D1;
                if (dist[up + (i + HW - 1) % HW] + D2 < d) d = dist[up + (i + HW - 1) % HW] + D2;
                if (dist[up + (i + 1) % HW] + D2 < d) d = dist[up + (i + 1) % HW] + D2;
            }
            dist[q] = d;
        }
    }
    for (let j = HH - 1; j >= 0; j--) {                     // 反向
        for (let i = HW - 1; i >= 0; i--) {
            const q = j * HW + i;
            if (dist[q] === 0) continue;
            let d = dist[j * HW + (i + 1) % HW] + D1;
            if (j < HH - 1) {
                const dn = (j + 1) * HW;
                if (dist[dn + i] + D1 < d) d = dist[dn + i] + D1;
                if (dist[dn + (i + 1) % HW] + D2 < d) d = dist[dn + (i + 1) % HW] + D2;
                if (dist[dn + (i + HW - 1) % HW] + D2 < d) d = dist[dn + (i + HW - 1) % HW] + D2;
            }
            dist[q] = d;
        }
    }

    /* ③ 人口潜势场 + ④ 像素着色（1024×512 逐像素） */
    const fCluster = makeField(8, 3, -1, 3, 0xC1713);       // 3 倍频值噪声，固定种子
    const canvas = mkCanvas(W, H), ctx = canvas.getContext('2d');
    const img = ctx.createImageData(W, H), px = img.data;

    /* dCoast 上采样列索引（x 环绕，同 earth.js:161-169） */
    const X0 = new Int32Array(W), X1 = new Int32Array(W), FX = new Float32Array(W);
    for (let i = 0; i < W; i++) {
        const gx = (i + 0.5) / W * HW - 0.5;
        let x0 = Math.floor(gx);
        FX[i] = gx - x0;
        if (x0 < 0) x0 += HW;
        X0[i] = x0;
        X1[i] = x0 + 1 === HW ? 0 : x0 + 1;
    }

    for (let j = 0; j < H; j++) {
        const v = (j + 0.5) / H;
        const lat = 90 - 180 * v;
        const ab = Math.abs(lat);
        let y0 = Math.floor(v * HH - 0.5);
        if (y0 < 0) y0 = 0;
        else if (y0 > HH - 2) y0 = HH - 2;
        const fy = v * HH - 0.5 - y0;
        const r0 = y0 * HW, r1 = r0 + HW;

        /* 温带/亚热带偏好（§3.2-3 复核修订点：第二项必须按【带符号】lat 求值——
         * 南半球 −50° 起加速衰减、−60° 归零；北半球恒为 1） */
        const latW = smoothstep(65, 55, ab) * smoothstep(-60, -50, lat);

        for (let i = 0; i < W; i++) {
            const k = (j * W + i) * 4;
            px[k + 3] = 255;
            if (latW === 0 || landAt(lat, 360 * (i + 0.5) / W) !== true) {
                px[k] = 0; px[k + 1] = 0; px[k + 2] = 0;    // 海洋/极地纯黑（契约严格项）
                continue;
            }

            /* dCoast 半分辨率双线性上采样（格距），沿海加成（1 格 ≈ 0.7° ≈ 78km） */
            const a0 = dist[r0 + X0[i]], a1 = dist[r0 + X1[i]];
            const b0 = dist[r1 + X0[i]], b1 = dist[r1 + X1[i]];
            const ax = a0 + (a1 - a0) * FX[i], bx = b0 + (b1 - b0) * FX[i];
            const dG = (ax + (bx - ax) * fy) / 3;           // chamfer 权重 → 格距
            const coast = Math.exp(-dG / 6);

            /* 3 倍频值噪声（倍频平均把分布压向 0.5）→ 对比度展开成簇间明暗（城乡对比） */
            const raw = nsAt(fCluster, (i + 0.5) / W * 8, v * 3.5 - 0.5);
            const cluster = clamp01(0.5 + (raw - 0.5) * 1.5);
            const P = cluster * latW * (0.42 + 0.58 * coast);

            /* 分档：P 低档纯黑 → 暗琥珀 (70,40,14) → 暖黄 (255,196,110)，指数提对比
             * （校准注：门槛取 0.36 时温带陆地点亮率 ~25%、腹地只剩稀疏灯珠，
             * 符合夜间卫星照片「沿海成片、内陆零星」的密度观感） */
            const t = clamp01((P - 0.36) / 0.64);
            let r = 0, g = 0, b = 0;
            if (t > 0) {
                const e = Math.pow(t, 1.35);
                r = mix(70, 255, e); g = mix(40, 196, e); b = mix(14, 110, e);
            }

            /* 1px 级小镇灯珠散点（hash 阈值；P 越高越密 → 沿海自然加密） */
            const dotP = smoothstep(0.14, 0.8, P) * 0.55;
            if (dotP > 0 && hash2(i, j, 0xD07) < dotP) {
                const br = 0.45 + 0.55 * hash2(i, j, 0xD08);
                const dr = 255 * br, dg = 200 * br, db = 115 * br;
                if (dr > r) r = dr;
                if (dg > g) g = dg;
                if (db > b) b = db;
            }
            px[k] = r; px[k + 1] = g; px[k + 2] = b;
        }
    }

    /* ⑤ 城市站点光斑：putImageData 之后再画矢量渐变（同 earth.js:425-437 顺序），
     * additive 叠加 + x±W 三重补画防经度缝（同 earth.js:358-360） */
    ctx.putImageData(img, 0, 0);
    ctx.globalCompositeOperation = 'lighter';
    for (let si = 0; si < sites.length; si++) {
        const s = sites[si];
        const tp = TIER[s.tier];
        const x = ((s.lon % 360) + 360) % 360 / 360 * W;
        const y = (90 - s.lat) / 180 * H;
        /* 3 层（T1/T2）：外晕暖黄 → 中层 → 近白内核；2 层（T3/T4）：外晕 + 内核 */
        const layers = tp.layers === 3
            ? [[1.0, 0.35, '255,196,110'], [0.55, 0.6, '255,214,150'], [0.28, 0.95, '255,236,190']]
            : [[1.0, 0.38, '255,200,120'], [0.42, 0.9, '255,230,180']];
        for (let li = 0; li < layers.length; li++) {
            const rr = tp.glowR * layers[li][0], aa = layers[li][1], col = layers[li][2];
            for (let ox = -W; ox <= W; ox += W) {           // 经度环绕补画
                const cx = x + ox;
                if (cx + rr < 0 || cx - rr > W) continue;
                const gr = ctx.createRadialGradient(cx, y, 0, cx, y, rr);
                gr.addColorStop(0, 'rgba(' + col + ',' + aa + ')');
                gr.addColorStop(1, 'rgba(' + col + ',0)');
                ctx.fillStyle = gr;
                ctx.fillRect(cx - rr, y - rr, rr * 2, rr * 2);
            }
        }
    }
    ctx.globalCompositeOperation = 'source-over';
    return canvas;
}

/* ========================= 入口 ========================= */

export function build(deps) {
    /* deps = { landAt, radius }；radius 本模块不用（统一签名，§3.1） */
    const sites = citySites(deps.landAt);
    const canvas = drawLights(deps.landAt, sites);
    const map = new THREE.CanvasTexture(canvas);
    map.colorSpace = THREE.SRGBColorSpace;
    return { map: map };
}
