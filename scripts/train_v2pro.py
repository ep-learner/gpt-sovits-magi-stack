# -*- coding: utf-8 -*-
r"""
GPT-SoVITS v2Pro 一键训练驱动（无头 / 命令行版）

复用 webui.py 中与 WebUI "一键训练" 完全相同的逻辑：
  open1abc -> 数据预处理（1a 文本/音素  1b HuBERT + SV  1c 语义）
  open1Ba  -> 训练 SoVITS (s2)
  open1Bb  -> 训练 GPT   (s1)

为什么不直接点 WebUI：
  webui.py 在模块底部会无条件执行 app.queue().launch() 启动服务，
  这里在 import 前把 gr.Blocks.launch 替换成空函数，即可在不启动服务的情况下
  复用其全部训练逻辑，保证参数、配置、路径与 WebUI 默认值完全一致。

用法（在整合包根目录外任意位置均可）：
  set GPT_SOVITS_ROOT=D:\GPT-SoVITS-stack\GPT-SoVITS-v2pro-20250604
  runtime\python.exe scripts\train_v2pro.py --exp xiangong --list output\asr_opt\xiangong.list --wav output\slicer_opt\xiangong

说明：
  * 训练参数全部使用 WebUI 默认值（v2Pro、关 DPO、关 LoRA、8G 卡自动 batch_size）。
  * 产出权重：SoVITS_weights_v2Pro\<exp>_*.pth、GPT_weights_v2Pro\<exp>*.ckpt
  * 运行前请关闭占用显存的程序（模拟器、游戏、视频播放器等）。
"""
import argparse
import os
import sys
import traceback

DEFAULT_ROOT = r"D:\GPT-SoVITS-stack\GPT-SoVITS-v2pro-20250604"


def drain(gen, label):
    """消费生成器；webui 的函数用 yield 推送进度，全部消费完才算跑完。"""
    print("\n===== %s =====" % label, flush=True)
    last = None
    try:
        for item in gen:
            if isinstance(item, (list, tuple)) and item:
                msg = item[0]
            else:
                msg = item
            if msg != last:
                print("  [进度]", msg, flush=True)
                last = msg
    except Exception:
        traceback.print_exc()
        raise
    print("===== %s 完成 =====" % label, flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.environ.get("GPT_SOVITS_ROOT", DEFAULT_ROOT),
                    help="GPT-SoVITS 整合包根目录")
    ap.add_argument("--exp", default="xiangong", help="实验名（权重文件前缀）")
    ap.add_argument("--list", dest="inp_text", required=True,
                    help="ASR 产出的 .list 标注文件路径")
    ap.add_argument("--wav", dest="inp_wav_dir", required=True,
                    help="切片音频所在目录")
    ap.add_argument("--stage", default="all", choices=["all", "1abc", "1Ba", "1Bb"],
                    help="只运行指定阶段（默认 all：1abc→1Ba→1Bb 依次执行）。"
                         "分阶段前台运行可避开单命令 10 分钟上限。")
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    if not os.path.isdir(root):
        sys.exit("整合包根目录不存在: " + root)
    os.chdir(root)
    sys.path.insert(0, root)

    # 阻止 import webui 时启动 Gradio 服务
    import gradio as gr
    gr.Blocks.launch = lambda self, *a, **k: None

    import webui  # noqa: E402  —— 会构建 UI 但不 launch
    from config import (  # noqa: E402
        pretrained_sovits_name, pretrained_gpt_name, bert_path, cnhubert_path,
    )

    version = "v2Pro"
    exp_name = args.exp
    inp_text = os.path.abspath(args.inp_text)
    inp_wav_dir = os.path.abspath(args.inp_wav_dir)
    gpus = webui.gpus  # 如 "0"

    if not os.path.exists(inp_text):
        sys.exit("标注文件不存在: " + inp_text)
    if not os.path.isdir(inp_wav_dir):
        sys.exit("切片目录不存在: " + inp_wav_dir)

    print("version    =", version)
    print("exp_name   =", exp_name)
    print("gpus       =", gpus)
    print("is_half    =", webui.is_half)
    print("batch_size (SoVITS) =", webui.default_batch_size)
    print("batch_size (GPT)    =", webui.default_batch_size_s1)
    print("inp_text   =", inp_text)
    print("inp_wav_dir=", inp_wav_dir, flush=True)

    pretrained_s2G = pretrained_sovits_name[version]
    pretrained_s2D = pretrained_s2G.replace("s2G", "s2D")
    pretrained_s1 = pretrained_gpt_name[version]
    print("pretrained_s2G =", pretrained_s2G)
    print("pretrained_s2D =", pretrained_s2D)
    print("pretrained_s1  =", pretrained_s1, flush=True)

    if args.stage in ("all", "1abc"):
        # ---- 1abc: 数据预处理 ----
        drain(webui.open1abc(
            version, inp_text, inp_wav_dir, exp_name,
            gpus, gpus, gpus,                  # gpu_numbers1a / 1Ba / 1c
            bert_path, cnhubert_path, pretrained_s2G,
        ), "1abc 数据预处理")

    if args.stage in ("all", "1Ba"):
        # ---- 1Ba: 训练 SoVITS (s2) ----
        drain(webui.open1Ba(
            version,
            webui.default_batch_size,          # batch_size
            webui.default_sovits_epoch,        # total_epoch (默认 8)
            exp_name,
            0.4,                               # text_low_lr_rate (UI 默认)
            True,                              # if_save_latest
            True,                              # if_save_every_weights
            webui.default_sovits_save_every_epoch,  # save_every_epoch (默认 4)
            gpus,
            pretrained_s2G,
            pretrained_s2D,
            False,                             # if_grad_ckpt (v2Pro 用不到)
            "32",                              # lora_rank (s2_train 对 v2Pro 忽略此项=全量微调)
        ), "1Ba SoVITS 训练")

    if args.stage in ("all", "1Bb"):
        # ---- 1Bb: 训练 GPT (s1) ----
        drain(webui.open1Bb(
            webui.default_batch_size_s1,       # batch_size
            15,                                # total_epoch (UI 默认 15)
            exp_name,
            False,                             # if_dpo (PRD: 关闭 DPO)
            True,                              # if_save_latest
            True,                              # if_save_every_weights
            5,                                 # save_every_epoch (UI 默认 5)
            gpus,
            pretrained_s1,
        ), "1Bb GPT 训练")

    print("\n[阶段 %s] 完成。权重位于：" % args.stage)
    print("  SoVITS_weights_v2Pro\\  和  GPT_weights_v2Pro\\")


if __name__ == "__main__":
    main()
