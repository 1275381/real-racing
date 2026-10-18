"""M14 30 发扩容弹匣（商店配件「30 发扩容匣」）：同截面钢匣下延 4.8 cm、匣底微前倾"""
import m14 as M
from _m14_part import meta

META = meta()


def build():
    M.magazine(drop=0.048, rake=0.006)
