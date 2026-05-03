#!/opt/homebrew/bin/bash
export PATH=/opt/homebrew/bin:$PATH
# 解析命令行参数
while getopts ":i:o:" opt; do
  case $opt in
  i)
    input_video=$OPTARG
    ;;
  o)
    output_gif=$OPTARG
    ;;
  *)
    echo "Usage: $0 -i <input_video> -o <output_gif>"
    exit 1
    ;;
  esac
done
# /opt/homebrew/bin/mediainfo

# 获取视频分辨率
#Width=$(mediainfo "$input_video" | grep "Width" | awk -F: '{print $2}' | sed 's/pixels//g' | sed 's/ //g')
#Height=$(mediainfo "$input_video" | grep "Height" | awk -F: '{print $2}' | sed 's/pixels//g' | sed 's/ //g')
Width=$(mediainfo "$input_video" | grep "Width" | awk -F: '{print $2}' | sed 's/pixels//g' | sed 's/ //g')
Height=$(mediainfo "$input_video" | grep "Height" | awk -F: '{print $2}' | sed 's/pixels//g' | sed 's/ //g')

echo "Width: $Width"
echo "Height: $Height"

# 使用ffmpeg将视频转换为gif
ffmpeg -i "$input_video" -v quiet "$output_gif"

# 获取gif文件大小
gif_size=$(du -sh "$output_gif" | awk '{print $1}')

echo "gif_size: $gif_size"

: <<'END'
# 检查参数是否正确
if [ $# -ne 2 ]; then
    echo "Usage: $0 input_video output_gif"
    echo "eg: ./covert-mp4-git.sh networ.mp4 networt.gif"
    exit 1
fi

input_video="$1"
output_gif="$2"

# 获取视频分辨率
Width=$(/opt/homebrew/bin/mediainfo "$input_video" | grep "Width" | awk -F: '{print $2}' | sed 's/pixels//g' | sed 's/ //g')
Height=$(/opt/homebrew/bin/mediainfo "$input_video" | grep "Height" | awk -F: '{print $2}' | sed 's/pixels//g' | sed 's/ //g')

echo "Width: $Width"
echo "Height: $Height"

# 使用ffmpeg将视频转换为gif
ffmpeg -i "$input_video" "$output_gif"
# 获取gif文件大小
gif_size=$(du -sh "$output_gif")

echo "gif_size: $gif_size"

END
