ffmpeg -i airpods.gif -vf "scale=iw/2:ih/2,fps=10" output.gif
➜  Downloads ffprobe -v quiet -print_format json -show_format -show_streams airpods.gif
{
    "streams": [
        {
            "index": 0,
            "codec_name": "gif",
            "codec_long_name": "CompuServe GIF (Graphics Interchange Format)",
            "codec_type": "video",
            "codec_tag_string": "[0][0][0][0]",
            "codec_tag": "0x0000",
            "width": 912,
            "height": 912,
            "coded_width": 912,
            "coded_height": 912,
            "closed_captions": 0,
            "film_grain": 0,
            "has_b_frames": 0,
            "pix_fmt": "bgra",
            "level": -99,
            "refs": 1,
            "r_frame_rate": "50/1",
            "avg_frame_rate": "50/1",
            "time_base": "1/100",
            "start_pts": 0,
            "start_time": "0.000000",
            "duration_ts": 1000,
            "duration": "10.000000",
            "nb_frames": "500",
            "disposition": {
                "default": 0,
                "dub": 0,
                "original": 0,
                "comment": 0,
                "lyrics": 0,
                "karaoke": 0,
                "forced": 0,
                "hearing_impaired": 0,
                "visual_impaired": 0,
                "clean_effects": 0,
                "attached_pic": 0,
                "timed_thumbnails": 0,
                "non_diegetic": 0,
                "captions": 0,
                "descriptions": 0,
                "metadata": 0,
                "dependent": 0,
                "still_image": 0,
                "multilayer": 0
            }
        }
    ],
    "format": {
        "filename": "airpods.gif",
        "nb_streams": 1,
        "nb_programs": 0,
        "nb_stream_groups": 0,
        "format_name": "gif",
        "format_long_name": "CompuServe Graphics Interchange Format (GIF)",
        "start_time": "0.000000",
        "duration": "10.000000",
        "size": "30896404",
        "bit_rate": "24717123",
        "probe_score": 100
    }
}


是的，可以先用 FFmpeg 查看 GIF 的详细信息（如帧数、帧率、尺寸、时长、比特率），然后根据这些数据评估压缩效果，再精细调整参数，避免过度砍帧或尺寸。 [cnblogs](https://www.cnblogs.com/Cycas/p/17650276.html)

## 查看 GIF 基础信息
运行这个命令，获取完整分析：
```
ffprobe -v quiet -print_format json -show_format -show_streams airpods.gif
```
- 输出会显示 `width`、`height`（尺寸）、`r_frame_rate`（帧率）、`nb_frames`（帧数）、`duration`（时长）、`bit_rate`（比特率）、`size`（文件大小）。
- 或者简单版：`ffprobe airpods.gif`，看 Duration、fps、resolution 等关键行。 [cnblogs](https://www.cnblogs.com/Cycas/p/17650276.html)

## 评估与预测大小
假设输出示例：
```
Duration: 00:00:05.00, fps=30, 150 frames, 1920x1080, bitrate=4.8Mbps
```
- **原大小估算**：30MB，5秒 × 30fps = 150帧，高清大图每帧约 200KB。
- **你的命令预测**：`scale=iw/2:ih/2`（尺寸 1/4），`fps=10`（帧数减至 50），预计大小降到 **6-10MB**（砍掉 2/3）。 [cnblogs](https://www.cnblogs.com/Cycas/p/17650276.html)

## 逐步优化命令
基于信息，渐进测试（每次改一处）：
```
# 1. 只降帧率：保持尺寸
ffmpeg -i airpods.gif -r 15 output1.gif

# 2. 只缩尺寸：保持原帧率
ffmpeg -i airpods.gif -vf "scale=960:540" output2.gif

# 3. 组合+调色板（高质量）
ffmpeg -i airpods.gif -vf "fps=15,scale=960:-1,palettegen" palette.png
ffmpeg -i airpods.gif -i palette.png -lavfi "fps=15,scale=960:-1[x];[x][1:v]paletteuse" output.gif

# 4. 目标 20MB：加比特率限制
ffmpeg -i airpods.gif -vf "scale=iw/1.5:ih/1.5,fps=12" -b:v 1.5M output.gif
```
每步后用 `ls -lh` 查大小，预览动画质量，逐步逼近 20MB。 [cnblogs](https://www.cnblogs.com/Cycas/p/17650276.html)

这样你能精确控制，先评估再动手，不会盲目砍太多！