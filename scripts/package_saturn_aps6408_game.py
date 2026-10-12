import argparse
import csv
import hashlib
import json
import shutil
import zipfile
from pathlib import Path


CORE_SHA = '34031f562b05b7c49b33c9d33ed1f98f50883b7ee75ef60139755d859fc6f17b'
SOURCE = 'bcff435025423293ca23c2e34bedfbab61537f93'
NAME = 'Saturn_APS6408_Game_20261012'


def package(rbf, output):
    assert rbf.stat().st_size == 4615740
    assert hashlib.sha256(rbf.read_bytes()).hexdigest() == CORE_SHA, 'Use the exact board-tested complete core'
    target = output / NAME
    archive = output / (NAME + '.zip')
    assert not target.exists() and not archive.exists(), 'Preserve existing releases'
    target.mkdir(parents=True)
    core = target / 'SD/_Console' / (NAME + '.rbf')
    core.parent.mkdir(parents=True)
    shutil.copyfile(rbf, core)
    config = bytearray(16)
    config[10] = 4
    cfg_path = target / 'SD/config/Saturn.CFG'
    cfg_path.parent.mkdir(parents=True)
    cfg_path.write_bytes(config)
    installer = Path(__file__).with_name('install_saturn_aps6408_game.ps1')
    shutil.copyfile(installer, target / 'Install.ps1')
    (target / '使用说明.md').write_text('''# Saturn APS6408 完整游戏测试核心

本包为完整 Saturn core，使用已完成8.47/16.93MHz实板诊断的位流。需要保留主SDRAM，并将APS6408接到RAMH接口；菜单可调PSRAM频率。默认配置为16.93MHz。

## 安装到MiSTer SD卡

推荐把SD卡接到Windows，在解压后的本目录运行（将H:换成实际盘符）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\\Install.ps1 -SdRoot H:\\
```

安装器核对核心SHA256、备份已有配置，只修改PSRAM频率位，保留其他Saturn设置。它只会将SHA完全匹配的旧自编诊断boot.rom备份后移走，已有真实BIOS不变。备份在卡根目录aps6408-game-backups。也可追加`-Frequency 8.47`选择初始低速。

手动安装：把`SD/_Console`中的RBF放入卡的`_Console`目录；初次没有Saturn.CFG时，可把`SD/config/Saturn.CFG`放入卡的`config`目录。已有CFG时请使用安装器，或在菜单手动调频，以保留原设置。原有核心文件可以保留。

## 启动游戏

1. 安全弹出SD卡，装回板卡，在MiSTer选择`Saturn_APS6408_Game_20261012`。
2. 使用自己的Saturn BIOS：菜单`Load bios`支持BIN文件；自动加载时放在`games/Saturn/boot.rom`。本包没有BIOS、游戏或自编诊断ROM。旧诊断boot.rom会显示测试画面，不能用于启动游戏。
3. 游戏镜像放入`games/Saturn`，通过`Insert Disc`选择CHD或CUE。CUE引用的音轨文件应保留在对应路径。按游戏需要选择`Region`和`Cartridge`；不确定区域可先选Auto。
4. 先用16.93MHz运行，再用8.47MHz对照。`PSRAM clock`位于主设置菜单。调频会复位游戏并重新训练PSRAM，因此每档重新进入同一游戏、同一场景比较。测试前保存游戏进度。

| 菜单频率 | 当前依据 | 用法 |
| --- | --- | --- |
| 8.47MHz | 完整1MiB诊断通过 | 低速对照 |
| 16.93MHz | 完整诊断多次通过 | 游戏测试起始档 |
| 33.87MHz | 完整诊断仍有读取错误 | 可测试启动、花屏和卡死；不能作为已通过档 |
| 50.80MHz EXP | 未完成实板验收 | 保留实验选项 |

这些选项改变PSRAM访问频率，不改变Saturn的标称CPU/视频频率。低速内存可能增加CPU等待，是否影响游戏流畅度由实际运行比较。`RAMH_SLOW=1`，没有改为快速RAMH接口。

每档建议运行同一场景10分钟以上，记录是否启动、画面速度、音频断续、花屏、卡死、运行时长；同一游戏尽量保持区域、扩展卡和其他设置一致。可填写`游戏测试结果.csv`。切换后重新打开菜单核对当前档位；如需下次继续使用，通过MiSTer的Save settings保存。

## 构建及验证范围

本包使用GitHub Runner37732550491、源码bcff435的原始完整位流，RBF SHA256见manifest.json。本轮只整理交付和默认CFG，没有重新综合或更换采样逻辑。位流与此前8/16MHz板测逐字节一致。

完整core在16.93MHz的默认诊断两次通过：四轮各1MiB无缓存写读、一轮缓存读取、六种部分写。独立诊断核另有两种16.93MHz全1MiB零错结果，但交付的RBF是完整Saturn核。

尚未做真实BIOS/游戏测试，整体STA仍未通过，33MHz问题未修复。因此这是供本板运行游戏验证的完整核心，尚不能称为完成时序与游戏验收的稳定发布。保留以往故障结果，实际游戏反馈请写回项目的编译与测试记录.md。
''', encoding='utf-8')
    with (target / '游戏测试结果.csv').open('w', encoding='utf-8-sig', newline='') as stream:
        writer = csv.writer(stream)
        writer.writerow(['日期', '游戏及镜像', '区域', '扩展卡', 'PSRAM_MHz', '场景', '运行分钟', '启动成功', '画面流畅', '音频正常', '花屏', '卡死', '备注'])
        for frequency in ('16.93', '8.47', '33.87'):
            writer.writerow(['', '', '', '', frequency, '', '', '', '', '', '', '', ''])
    manifest = {
        'name': NAME, 'date': '2026-10-12', 'purpose': 'Complete Saturn core for user game testing',
        'source_commit': SOURCE, 'runner': 37732550491,
        'runner_url': 'https://github.com/jiang-dongwei/Saturn_MiSTer/actions/runs/37732550491',
        'new_quartus_build': False, 'rbf_bytes': core.stat().st_size, 'rbf_sha256': CORE_SHA,
        'default_psram_mhz': 16.9344, 'default_from': 'Bundled CFG or installer, not a changed HDL default',
        'osd_mhz': [33.8688, 16.9344, 8.4672, 50.8032], 'frequency_status_bits': [82, 83],
        'configuration_name': 'Saturn.CFG', 'cfg_byte10_mode_mask': 12,
        'core_name': 'Saturn', 'ramh_slow': 1,
        'validation': {'8MHz_full_diagnostic': 'PASS', '16MHz_full_diagnostic': 'PASS',
                       '33MHz_full_diagnostic': 'FAIL', '50MHz_board': 'NOT_ACCEPTED',
                       'overall_sta': 'FAIL', 'bios_and_games': 'NOT_TESTED'},
        'bios_or_games_included': False,
    }
    files = sorted(p for p in target.rglob('*') if p.is_file())
    manifest['files'] = {p.relative_to(target).as_posix(): {
        'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest(),
    } for p in files}
    (target / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    files = sorted(p for p in target.rglob('*') if p.is_file())
    (target / 'SHA256SUMS.txt').write_text(''.join(
        hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.relative_to(target).as_posix() + '\n'
        for p in files), encoding='utf-8')
    with zipfile.ZipFile(archive, 'x', compression=zipfile.ZIP_DEFLATED) as bundle:
        for path in sorted(p for p in target.rglob('*') if p.is_file()):
            bundle.write(path, path.relative_to(output).as_posix())
    with zipfile.ZipFile(archive) as bundle:
        assert bundle.testzip() is None
        for path in sorted(p for p in target.rglob('*') if p.is_file()):
            assert bundle.read(path.relative_to(output).as_posix()) == path.read_bytes()
        assert bundle.read(NAME + '/SD/config/Saturn.CFG') == bytes(10) + b'\x04' + bytes(5)
    print(json.dumps({'directory': str(target.resolve()), 'zip': str(archive.resolve()),
                      'zip_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
                      'rbf_sha256': CORE_SHA}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--rbf', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    package(args.rbf, args.output)
