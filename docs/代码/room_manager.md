# RoomManager 退役说明

> 权威范围：本页只记录该模块的公共契约、可观察行为、schema、所有权与依赖边界；私有实现和逐测试记录不进入本文档。

> 本文档只用于追溯 ADR #127/#128。ADR #142 已用 9×9 模块连续大地图取代线性手工房间方向；`RoomManager`、房间 marker、演示场景、`rooms.json`、`room_sequences.json`、启动参数与 `room-switch-smoke` 均已删除。

当前实现、数据格式、扩展点和测试义务以 `docs/代码/module_world_manager.md` 为准。不要恢复旧 carrier，也不要把本页作为新实现入口。
