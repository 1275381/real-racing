"""瞄具共用件：坐标原点 = 镜座安装面中心（游戏 _scope_visual 的 (0, top_y, mid_z)），
真实尺寸 ×1.2（与枪模同档放大），不缩放导出（length=None）。"""
from gun_kit import Group, side, cyl


def rail_clamp(z0, z1, half_w=0.0205, zone="alu", bolt_z=None):
    """皮卡汀尼夹座：两侧夹爪包住导轨（下探到导轨两侧）+ 横穿螺栓（左槽头右六角螺母）"""
    g = Group()
    for sx in (-1, 1):
        g.side([(z0, -0.0055), (z1, -0.0055), (z1, 0.004), (z0, 0.004)],
               sx * 0.0109 if sx > 0 else -half_w, half_w if sx > 0 else -0.0109)
    g.done("clamp_jaws", zone, bevel=0.0007)
    bz = bolt_z if bolt_z is not None else (z0 + z1) * 0.5
    cyl("clamp_bolt", (0.0, -0.0022, bz), 0.0026, half_w * 2 + 0.006, "steel", axis="x", segs=12)
    g = Group()
    g.lathe([(half_w + 0.0005, 0.0048), (half_w + 0.0045, 0.0048)], cx=-0.0022, cy=bz, segs=6, axis="x")
    g.lathe([(-half_w - 0.0035, 0.0042), (-half_w - 0.0005, 0.0042)], cx=-0.0022, cy=bz, segs=20, axis="x")
    g.done("clamp_nut", "steel", bevel=0.0004)
