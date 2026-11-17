#!/opt/homebrew/bin/bash

# =============================================================================
# Video Text Watermark Adder
# =============================================================================
#
# 功能:
# - 在视频右下角添加纯文字水印
# - 支持多种视频格式输入输出
# - 可自定义水印文本、位置、字体大小和颜色
#
# 作者: Kiro AI Assistant
# 版本: 1.0
# =============================================================================

set -euo pipefail

export PATH=/opt/homebrew/bin:$PATH

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- 全局变量 ---
SCRIPT_NAME=$(basename "$0")
DEFAULT_FONT_SIZE=48
DEFAULT_TEXT="By Postfix 念"
DEFAULT_POSITION="右下角"
VERBOSE=false
FORCE=false

# --- 日志函数 ---
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%H:%M:%S')

    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} [$timestamp] $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} [$timestamp] $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} [$timestamp] $message"
            ;;
        "DEBUG")
            if [ "$VERBOSE" = true ]; then
                echo -e "${BLUE}[DEBUG]${NC} [$timestamp] $message"
            fi
            ;;
        "SUCCESS")
            echo -e "${CYAN}[SUCCESS]${NC} [$timestamp] $message"
            ;;
    esac
}

# --- 帮助信息 ---
show_help() {
    local green=$(printf '\033[0;32m')
    local yellow=$(printf '\033[1;33m')
    local blue=$(printf '\033[0;34m')
    local nc=$(printf '\033[0m')

    printf "${green}%s${nc} - Video Text Watermark Adder\n\n" "$SCRIPT_NAME"

    printf "${yellow}用法:${nc}\n"
    printf "    %s [选项] -i <input_video> -o <output_video>\n\n" "$SCRIPT_NAME"

    printf "${yellow}必需参数:${nc}\n"
    printf "    ${blue}-i, --input FILE${nc}       输入视频文件\n"
    printf "    ${blue}-o, --output FILE${nc}      输出视频文件名\n\n"

    printf "${yellow}可选参数:${nc}\n"
    printf "    ${blue}-t, --text TEXT${nc}        水印文字 (默认: \"%s\")\n" "$DEFAULT_TEXT"
    printf "    ${blue}-s, --font-size SIZE${nc}   字体大小 (默认: %d)\n" "$DEFAULT_FONT_SIZE"
    printf "    ${blue}-c, --color COLOR${nc}      字体颜色 (默认: white)\n"
    printf "    ${blue}-p, --position POS${nc}      水印位置 (默认: 右下角)\n"
    printf "    ${blue}-v, --verbose${nc}          详细输出\n"
    printf "    ${blue}--force${nc}                强制覆盖已存在的文件\n"
    printf "    ${blue}-h, --help${nc}             显示此帮助信息\n\n"

    printf "${yellow}位置选项:${nc}\n"
    printf "    - top-left     左上角\n"
    printf "    - top-right    右上角\n"
    printf "    - bottom-left  左下角\n"
    printf "    - bottom-right 右下角 (默认)\n\n"

    printf "${yellow}示例:${nc}\n"
    printf "    # 基本使用\n"
    printf "    %s -i video.mp4 -o output.mp4\n\n" "$SCRIPT_NAME"
    printf "    # 自定义水印文字\n"
    printf "    %s -i video.mp4 -o output.mp4 -t \"My Watermark\"\n\n" "$SCRIPT_NAME"
    printf "    # 调整字体大小和颜色\n"
    printf "    %s -i video.mp4 -o output.mp4 -s 36 -c yellow\n\n" "$SCRIPT_NAME"
}

# --- 参数解析 ---
parse_arguments() {
    local input_video=""
    local output_video=""
    local font_size="$DEFAULT_FONT_SIZE"
    local text="$DEFAULT_TEXT"
    local color="white"
    local position="bottom-right"

    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--input)
                input_video="$2"
                shift 2
                ;;
            -o|--output)
                output_video="$2"
                shift 2
                ;;
            -t|--text)
                text="$2"
                shift 2
                ;;
            -s|--font-size)
                font_size="$2"
                if ! [[ "$font_size" =~ ^[0-9]+$ ]] || [ "$font_size" -lt 10 ] || [ "$font_size" -gt 200 ]; then
                    log "ERROR" "字体大小必须是10-200之间的整数"
                    exit 1
                fi
                shift 2
                ;;
            -c|--color)
                color="$2"
                shift 2
                ;;
            -p|--position)
                position="$2"
                if [[ ! "$position" =~ ^(top-left|top-right|bottom-left|bottom-right)$ ]]; then
                    log "ERROR" "位置必须是 top-left, top-right, bottom-left 或 bottom-right"
                    exit 1
                fi
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log "ERROR" "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done

    export INPUT_VIDEO="$input_video"
    export OUTPUT_VIDEO="$output_video"
    export WATERMARK_TEXT="$text"
    export FONT_SIZE="$font_size"
    export FONT_COLOR="$color"
    export POSITION="$position"
}

# --- 验证参数 ---
validate_arguments() {
    if [ -z "$INPUT_VIDEO" ] || [ -z "$OUTPUT_VIDEO" ]; then
        log "ERROR" "缺少必需参数"
        show_help
        exit 1
    fi

    if [ ! -f "$INPUT_VIDEO" ]; then
        log "ERROR" "输入视频文件不存在: $INPUT_VIDEO"
        exit 1
    fi

    if [ -f "$OUTPUT_VIDEO" ] && [ "$FORCE" = false ]; then
        log "ERROR" "输出文件已存在: $OUTPUT_VIDEO"
        log "INFO" "使用 --force 选项强制覆盖"
        exit 1
    fi

    local output_dir
    output_dir=$(dirname "$OUTPUT_VIDEO")
    if [ ! -w "$output_dir" ]; then
        log "ERROR" "输出目录不可写: $output_dir"
        exit 1
    fi

    log "DEBUG" "参数验证通过"
}

# --- 检查依赖 ---
check_dependencies() {
    if ! command -v ffmpeg &> /dev/null; then
        log "ERROR" "依赖 'ffmpeg' 未找到，请先安装"
        log "INFO" "安装方法: brew install ffmpeg"
        exit 1
    fi

    log "DEBUG" "所有依赖检查通过"
}

# --- 获取视频信息 ---
get_video_info() {
    local video_file="$1"

    log "DEBUG" "获取视频信息: $video_file"

    local width height duration
    width=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=width -of csv=p=0 "$video_file" 2>/dev/null)
    height=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=height -of csv=p=0 "$video_file" 2>/dev/null)
    duration=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$video_file" 2>/dev/null)

    log "DEBUG" "视频分辨率: ${width}x${height}"
    log "DEBUG" "视频时长: ${duration}秒"

    echo "${width}:${height}:${duration}"
}

# --- 计算水印位置 ---
calculate_position() {
    local width="$1"
    local height="$2"
    local font_size="$3"
    local position="$4"

    local margin=20
    local padding=10

    case "$position" in
        "top-left")
            echo "x=${padding}:y=${padding}"
            ;;
        "top-right")
            echo "x=W-tw-${padding}:y=${padding}"
            ;;
        "bottom-left")
            echo "x=${padding}:y=H-th-${padding}"
            ;;
        "bottom-right")
            echo "x=W-tw-${padding}:y=H-th-${padding}"
            ;;
    esac
}

# --- 执行ffmpeg添加水印 ---
add_watermark() {
    local input_video="$1"
    local output_video="$2"
    local text="$3"
    local font_size="$4"
    local color="$5"
    local position="$6"

    log "INFO" "开始添加水印..."
    log "INFO" "输入: $input_video"
    log "INFO" "输出: $output_video"
    log "INFO" "水印文字: $text"
    log "INFO" "字体大小: $font_size"
    log "INFO" "字体颜色: $color"
    log "INFO" "位置: $position"

    local video_info
    video_info=$(get_video_info "$input_video")

    local width height duration
    IFS=':' read -r width height duration <<< "$video_info"

    local pos
    pos=$(calculate_position "$width" "$height" "$font_size" "$position")

    local font_color_hex
    case "$color" in
        "white")  font_color_hex="FFFFFF" ;;
        "black")  font_color_hex="000000" ;;
        "yellow") font_color_hex="FFFF00" ;;
        "red")    font_color_hex="FF0000" ;;
        "green")  font_color_hex="00FF00" ;;
        "blue")   font_color_hex="0000FF" ;;
        *)        font_color_hex="FFFFFF" ;;
    esac

    local draw_text="drawtext=text='${text}':fontfile=/System/Library/Fonts/Helvetica.ttc:fontsize=${font_size}:fontcolor=${font_color_hex}:${pos}:borderw=2:bordercolor=00000040"

    log "DEBUG" "滤镜: $draw_text"

    local error_output
    error_output=$(ffmpeg -i "$input_video" \
        -vf "$draw_text" \
        -c:a copy \
        -y "$output_video" 2>&1)
    local ffmpeg_exit_code=$?

    if [ $ffmpeg_exit_code -ne 0 ]; then
        log "ERROR" "水印添加失败，退出码: $ffmpeg_exit_code"
        log "ERROR" "错误信息: $error_output"
        return 1
    fi

    if [ ! -f "$output_video" ]; then
        log "ERROR" "输出文件未生成: $output_video"
        return 1
    fi

    local file_size
    file_size=$(ls -lh "$output_video" 2>/dev/null | awk '{print $5}')
    log "SUCCESS" "水印添加完成，输出文件: $output_video ($file_size)"

    return 0
}

# --- 主函数 ---
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Video Text Watermark Adder v1.0${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    check_dependencies

    parse_arguments "$@"

    validate_arguments

    if ! add_watermark "$INPUT_VIDEO" "$OUTPUT_VIDEO" "$WATERMARK_TEXT" "$FONT_SIZE" "$FONT_COLOR" "$POSITION"; then
        log "ERROR" "处理失败"
        exit 1
    fi

    log "SUCCESS" "处理完成！"
}

# --- 脚本入口 ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi