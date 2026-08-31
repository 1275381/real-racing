// 车型清单：id 必须与 tools/blender/specs/<id>.py 及 assets/car_<id>.glb 一致。
// 全部由 Blender 程序化建模导出（见 tools/blender/buildCar.py），共用同一套命名契约：
// BodyPivot / HubXX / WheelXX / CaliperXX，材质 Paint(主色) Accent(副色) TailLight(刹车灯)。
export const CAR_MODELS = [
    { id: 'gt3', name: 'GT3 战驹', file: 'assets/car_gt3.glb', desc: '宽体包覆 · 鹅颈尾翼 · 均衡好开' },
    { id: 'hyper', name: '原型超跑', file: 'assets/car_hyper.glb', desc: '极低重心 · 鲨鱼鳍 · 双层尾翼' },
    { id: 'formula', name: '方程式', file: 'assets/car_formula.glb', desc: '开轮单体壳 · Halo · 多层前后翼' },
    { id: 'muscle', name: '肌肉房车', file: 'assets/car_muscle.glb', desc: '方正宽体 · 增压进气罩 · 侧排气' },
    { id: 'rally', name: '拉力战车', file: 'assets/car_rally.glb', desc: '高底盘两厢 · 四射灯 · 大尾翼' },
];

export const DEFAULT_MODEL = 'gt3';
export const modelById = (id) => CAR_MODELS.find((m) => m.id === id) || CAR_MODELS[0];
