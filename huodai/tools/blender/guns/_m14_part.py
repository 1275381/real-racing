"""M14 可换部件共用：与 m14 本体同一 ref/target 与同一缩放倍率（本体导出时打印的 k），
部件 GLB 直接落在本体的游戏枪身局部坐标里，游戏端原点叠放即对位。"""
import m14 as M

K_M14 = 1.042963    # make_gun m14 打印的 k（本体全长 → 程序化 M14 全长 1.1795）


def meta():
    return dict(ref=M.META["ref"], target=M.META["target"], length=None, scale=K_M14, size=1024)
