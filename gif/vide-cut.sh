#!/opt/homebrew/bin/bash

# =============================================================================
# Video to GIF Converter with Smart Splitting
# =============================================================================
#
# 功能:
# - 将视频片段转换为GIF
# - 自动检测文件大小并智能拆分
# - 支持多种时间格式输入
# - 提供质量和大小优化选项
# - 详细的进度显示和错误处理
#
# 作者: Kiro AI Assistant
# 版本: 2.1 (简化版)
# =============================================================================

set -euo pipefail

# 确保使用 Homebrew 的工具
export PATH=/opt/homebrew/bin:$PATH

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- 全局变量 ---
SCRIPT_NAME=$(basename "$0")
MAX_SIZE_MB=18
DEFAULT_FPS=10
DEFAULT_WIDTH=800
VERBOSE=false
FORCE=false
QUALITY="medium"

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
    cat << EOF
${GREEN}$SCRIPT_NAME - Video to GIF Converter${NC}

${YELLOW}用法:${NC}
    $SCRIPT_NAME [选项] -i <input_video> -o <output_gif> -s <start_time> -e <end_time>

${YELLOW}必需参数:${NC}
    ${BLUE}-i, --input FILE${NC}       输入视频文件
    ${BLUE}-o, --output FILE${NC}      输出GIF文件名
    ${BLUE}-s, --start TIME${NC}       开始时间 (格式: MM:SS 或 秒数)
    ${BLUE}-e, --end TIME${NC}         结束时间 (格式: MM:SS 或 秒数)

${YELLOW}可选参数:${NC}
    ${BLUE}-f, --fps NUMBER${NC}       帧率 (默认: $DEFAULT_FPS)
    ${BLUE}-w, --width NUMBER${NC}     宽度 (默认: $DEFAULT_WIDTH, 高度自动)
    ${BLUE}-q, --quality LEVEL${NC}    质量等级 (low/medium/high, 默认: $QUALITY)
    ${BLUE}-m, --max-size SIZE${NC}    最大文件大小MB (默认: $MAX_SIZE_MB)
    ${BLUE}-v, --verbose${NC}          详细输出
    ${BLUE}--force${NC}                强制覆盖已存在的文件
    ${BLUE}-h, --help${NC}             显示此帮助信息

${YELLOW}时间格式:${NC}
    - MM:SS (例如: 01:30 表示1分30秒)
    - 秒数 (例如: 90 表示90秒)
    - HH:MM:SS (例如: 00:01:30)

${YELLOW}质量等级说明:${NC}
    - ${PURPLE}low${NC}:    较小文件，较低质量 (fps=8)
    - ${PURPLE}medium${NC}: 平衡质量和大小 (fps=10, 默认)
    - ${PURPLE}high${NC}:   较高质量，较大文件 (fps=15)

${YELLOW}示例:${NC}
    # 基本使用
    $SCRIPT_NAME -i video.mp4 -o output.gif -s 00:30 -e 01:00

    # 高质量转换
    $SCRIPT_NAME -i video.mp4 -o output.gif -s 30 -e 90 -q high -f 15

    # 自定义大小和宽度
    $SCRIPT_NAME -i video.mp4 -o output.gif -s 00:30 -e 01:00 -w 600 -m 10

    # 详细输出模式
    $SCRIPT_NAME -v -i video.mp4 -o output.gif -s 00:30 -e 01:00

EOF
}

# --- 参数解析 ---
parse_arguments() {
    local input_video=""
    local output_gif=""
    local start_time=""
    local end_time=""
    local fps="$DEFAULT_FPS"
    local width="$DEFAULT_WIDTH"

    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--input)
                input_video="$2"
                shift 2
                ;;
            -o|--output)
                output_gif="$2"
                shift 2
                ;;
            -s|--start)
                start_time="$2"
                shift 2
                ;;
            -e|--end)
                end_time="$2"
                shift 2
                ;;
            -f|--fps)
                fps="$2"
                if ! [[ "$fps" =~ ^[0-9]+$ ]] || [ "$fps" -lt 1 ] || [ "$fps" -gt 30 ]; then
                    log "ERROR" "帧率必须是1-30之间的整数"
                    exit 1
                fi
                shift 2
                ;;
            -w|--width)
                width="$2"
                if ! [[ "$width" =~ ^[0-9]+$ ]] || [ "$width" -lt 100 ] || [ "$width" -gt 2000 ]; then
                    log "ERROR" "宽度必须是100-2000之间的整数"
                    exit 1
                fi
                shift 2
                ;;
            -q|--quality)
                QUALITY="$2"
                if [[ ! "$QUALITY" =~ ^(low|medium|high)$ ]]; then
                    log "ERROR" "质量等级必须是 low, medium 或 high"
                    exit 1
                fi
                shift 2
                ;;
            -m|--max-size)
                MAX_SIZE_MB="$2"
                if ! [[ "$MAX_SIZE_MB" =~ ^[0-9]+$ ]] || [ "$MAX_SIZE_MB" -lt 1 ]; then
                    log "ERROR" "最大文件大小必须是正整数"
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

    # 导出变量供其他函数使用
    export INPUT_VIDEO="$input_video"
    export OUTPUT_GIF="$output_gif"
    export START_TIME="$start_time"
    export END_TIME="$end_time"
    export FPS="$fps"
    export WIDTH="$width"
}

# --- 验证参数 ---
validate_arguments() {
    # 检查必需参数
    if [ -z "$INPUT_VIDEO" ] || [ -z "$OUTPUT_GIF" ] || [ -z "$START_TIME" ] || [ -z "$END_TIME" ]; then
        log "ERROR" "缺少必需参数"
        show_help
        exit 1
    fi

    # 检查输入文件是否存在
    if [ ! -f "$INPUT_VIDEO" ]; then
        log "ERROR" "输入视频文件不存在: $INPUT_VIDEO"
        exit 1
    fi

    # 检查输出文件是否已存在
    if [ -f "$OUTPUT_GIF" ] && [ "$FORCE" = false ]; then
        log "ERROR" "输出文件已存在: $OUTPUT_GIF"
        log "INFO" "使用 --force 选项强制覆盖"
        exit 1
    fi

    # 检查输出目录是否可写
    local output_dir
    output_dir=$(dirname "$OUTPUT_GIF")
    if [ ! -w "$output_dir" ]; then
        log "ERROR" "输出目录不可写: $output_dir"
        exit 1
    fi

    log "DEBUG" "参数验证通过"
}

# --- 检查依赖 ---
check_dependencies() {
    local deps=("ffmpeg" "bc" "du")

    log "DEBUG" "检查依赖工具..."
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log "ERROR" "依赖 '$dep' 未找到，请先安装"
            case $dep in
                "ffmpeg")
                    log "INFO" "安装方法: brew install ffmpeg"
                    ;;
                "bc")
                    log "INFO" "安装方法: brew install bc"
                    ;;
            esac
            exit 1
        fi
    done

    log "DEBUG" "所有依赖检查通过"
}

# --- 时间转换函数 (增强版) ---
convert_to_seconds() {
    local time="$1"
    
    # 如果已经是纯数字，直接返回
    if [[ "$time" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "$time"
        return
    fi
    
    # 处理 HH:MM:SS 格式
    if [[ "$time" =~ ^[0-9]+:[0-9]+:[0-9]+$ ]]; then
        local hours minutes seconds
        IFS=':' read -r hours minutes seconds <<< "$time"
        echo "$((hours * 3600 + minutes * 60 + seconds))"
        return
    fi
    
    # 处理 MM:SS 格式
    if [[ "$time" =~ ^[0-9]+:[0-9]+$ ]]; then
        local minutes seconds
        IFS=':' read -r minutes seconds <<< "$time"
        echo "$((minutes * 60 + seconds))"
        return
    fi
    
    log "ERROR" "无效的时间格式: $time"
    log "INFO" "支持的格式: HH:MM:SS, MM:SS, 或纯秒数"
    exit 1
}

# --- 获取视频信息 ---
get_video_info() {
    local video_file="$1"
    
    log "DEBUG" "获取视频信息: $video_file"
    
    # 获取视频时长
    local duration
    duration=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$video_file" 2>/dev/null)
    
    if [ -z "$duration" ] || [ "$duration" = "N/A" ]; then
        log "ERROR" "无法获取视频时长"
        exit 1
    fi
    
    # 获取视频分辨率
    local resolution
    resolution=$(ffprobe -v quiet -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$video_file" 2>/dev/null)
    
    log "DEBUG" "视频时长: ${duration}秒"
    log "DEBUG" "视频分辨率: $resolution"
    
    echo "$duration"
}

# --- 验证时间范围 ---
validate_time_range() {
    local start_seconds="$1"
    local end_seconds="$2"
    local video_duration="$3"
    
    # 检查开始时间是否有效
    if (( $(echo "$start_seconds < 0" | bc -l) )); then
        log "ERROR" "开始时间不能为负数"
        exit 1
    fi
    
    # 检查结束时间是否大于开始时间
    if (( $(echo "$end_seconds <= $start_seconds" | bc -l) )); then
        log "ERROR" "结束时间必须大于开始时间"
        exit 1
    fi
    
    # 检查时间是否超出视频长度
    if (( $(echo "$end_seconds > $video_duration" | bc -l) )); then
        log "WARN" "结束时间超出视频长度，将调整为视频结尾"
        end_seconds="$video_duration"
    fi
    
    echo "$end_seconds"
}

# --- 根据质量等级设置参数 ---
set_quality_params() {
    case "$QUALITY" in
        "low")
            FPS=8
            ;;
        "medium")
            FPS=10
            ;;
        "high")
            FPS=15
            ;;
    esac
    
    log "DEBUG" "质量等级: $QUALITY (FPS: $FPS)"
}

# --- 生成GIF ---
generate_gif() {
    local input_video="$1"
    local output_gif="$2"
    local start_seconds="$3"
    local duration="$4"
    
    log "INFO" "开始生成GIF..."
    log "INFO" "输入: $input_video"
    log "INFO" "输出: $output_gif"
    log "INFO" "时间段: ${start_seconds}s - $((start_seconds + duration))s (${duration}s)"
    log "INFO" "参数: ${WIDTH}px宽度, ${FPS}fps, 质量=${QUALITY}"
    
    # 构建视频滤镜
    local video_filters="fps=${FPS},scale=${WIDTH}:-1:flags=lanczos"
    
    # 直接生成GIF（简化方法）
    log "INFO" "生成GIF..."
    local ffmpeg_cmd=(
        ffmpeg -i "$input_video"
        -ss "$start_seconds" -t "$duration"
        -vf "$video_filters"
        -y "$output_gif"
    )
    
    log "DEBUG" "执行GIF生成命令: ${ffmpeg_cmd[*]}"
    
    # 执行GIF生成，捕获错误
    local gif_error
    if [ "$VERBOSE" = true ]; then
        "${ffmpeg_cmd[@]}"
        local gif_exit_code=$?
    else
        gif_error=$("${ffmpeg_cmd[@]}" 2>&1)
        local gif_exit_code=$?
    fi
    
    if [ $gif_exit_code -ne 0 ]; then
        log "ERROR" "GIF生成失败，退出码: $gif_exit_code"
        if [ -n "$gif_error" ]; then
            log "ERROR" "错误信息: $gif_error"
        fi
        return 1
    fi
    
    # 检查文件是否生成成功
    if [ ! -f "$output_gif" ]; then
        log "ERROR" "GIF文件未生成: $output_gif"
        return 1
    fi
    
    # 检查文件大小
    local file_size
    file_size=$(ls -lh "$output_gif" 2>/dev/null | awk '{print $5}')
    log "SUCCESS" "GIF生成完成，文件大小: $file_size"
    
    return 0
}

# --- 获取文件大小 (MB) ---
get_file_size_mb() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        echo "0"
        return
    fi
    
    # 获取文件大小（字节）
    local size_bytes
    if command -v stat >/dev/null 2>&1; then
        # macOS 和 Linux 兼容
        size_bytes=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
    else
        # 备用方法
        size_bytes=$(wc -c < "$file")
    fi
    
    # 转换为MB
    local size_mb
    size_mb=$(echo "scale=2; $size_bytes / 1024 / 1024" | bc)
    
    echo "$size_mb"
}

# --- 智能拆分GIF ---
split_gif() {
    local input_video="$1"
    local output_gif="$2"
    local start_seconds="$3"
    local duration="$4"
    local file_size_mb="$5"
    
    log "WARN" "文件大小 ${file_size_mb}MB 超过限制 ${MAX_SIZE_MB}MB，开始智能拆分..."
    
    # 计算需要拆分的段数（向上取整）
    local segments
    segments=$(echo "($file_size_mb + $MAX_SIZE_MB - 1) / $MAX_SIZE_MB" | bc)
    
    # 确保至少拆分为2段
    if [ "$segments" -lt 2 ]; then
        segments=2
    fi
    
    local segment_duration
    segment_duration=$(echo "scale=2; $duration / $segments" | bc -l)
    
    log "INFO" "将拆分为 $segments 段，每段约 ${segment_duration}秒"
    
    # 创建输出目录
    local output_dir="${output_gif%.*}_splits"
    mkdir -p "$output_dir"
    
    log "INFO" "输出目录: $output_dir"
    
    # 生成各个片段
    for ((i = 0; i < segments; i++)); do
        local segment_start
        segment_start=$(echo "$start_seconds + ($i * $segment_duration)" | bc -l)
        
        local segment_file="${output_dir}/$(basename "${output_gif%.*}")_part$(printf "%03d" $((i + 1))).gif"
        
        log "INFO" "生成片段 $((i + 1))/$segments: $(basename "$segment_file")"
        
        # 生成片段GIF（简化方法）
        local video_filters="fps=${FPS},scale=${WIDTH}:-1:flags=lanczos"
        
        local segment_cmd=(
            ffmpeg -i "$input_video"
            -ss "$segment_start" -t "$segment_duration"
            -vf "$video_filters"
            -y "$segment_file"
        )
        
        if [ "$VERBOSE" = true ]; then
            "${segment_cmd[@]}"
        else
            "${segment_cmd[@]}" >/dev/null 2>&1
        fi
        
        # 检查片段是否生成成功
        if [ -f "$segment_file" ]; then
            local segment_size
            segment_size=$(get_file_size_mb "$segment_file")
            log "SUCCESS" "片段 $((i + 1)) 完成 (${segment_size}MB): $(basename "$segment_file")"
        else
            log "ERROR" "片段 $((i + 1)) 生成失败"
        fi
    done
    
    # 删除原始的大文件
    if [ -f "$output_gif" ]; then
        rm "$output_gif"
        log "INFO" "已删除原始大文件"
    fi
    
    # 显示拆分结果
    log "SUCCESS" "文件已拆分完成，保存在目录: $output_dir"
    
    # 列出生成的文件
    if [ "$VERBOSE" = true ]; then
        log "INFO" "生成的文件列表:"
        ls -lh "$output_dir"/*.gif 2>/dev/null | while read -r line; do
            log "INFO" "  $line"
        done
    fi
}

# --- 主处理函数 ---
process_video() {
    # 获取视频信息
    local video_duration
    video_duration=$(get_video_info "$INPUT_VIDEO")
    
    # 转换时间格式
    local start_seconds end_seconds
    start_seconds=$(convert_to_seconds "$START_TIME")
    end_seconds=$(convert_to_seconds "$END_TIME")
    
    # 验证时间范围
    end_seconds=$(validate_time_range "$start_seconds" "$end_seconds" "$video_duration")
    
    # 计算持续时间
    local duration
    duration=$(echo "$end_seconds - $start_seconds" | bc -l)
    
    log "INFO" "时间信息:"
    log "INFO" "  视频总长度: ${video_duration}秒"
    log "INFO" "  开始时间: ${start_seconds}秒"
    log "INFO" "  结束时间: ${end_seconds}秒"
    log "INFO" "  截取时长: ${duration}秒"
    
    # 设置质量参数
    set_quality_params
    
    # 生成GIF
    if ! generate_gif "$INPUT_VIDEO" "$OUTPUT_GIF" "$start_seconds" "$duration"; then
        log "ERROR" "GIF生成失败"
        exit 1
    fi
    
    # 检查文件大小
    local file_size_mb
    file_size_mb=$(get_file_size_mb "$OUTPUT_GIF")
    
    log "INFO" "生成的GIF大小: ${file_size_mb}MB"
    
    # 如果文件过大，进行拆分
    if (( $(echo "$file_size_mb > $MAX_SIZE_MB" | bc -l) )); then
        split_gif "$INPUT_VIDEO" "$OUTPUT_GIF" "$start_seconds" "$duration" "$file_size_mb"
    else
        log "SUCCESS" "文件大小在 ${MAX_SIZE_MB}MB 限制内，无需拆分"
        log "SUCCESS" "最终输出: $OUTPUT_GIF (${file_size_mb}MB)"
        
        # 显示文件信息
        if command -v file >/dev/null 2>&1; then
            local file_info
            file_info=$(file "$OUTPUT_GIF")
            log "INFO" "文件信息: $file_info"
        fi
    fi
}

# --- 主函数 ---
main() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Video to GIF Converter v2.1${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # 检查依赖
    check_dependencies
    
    # 解析参数
    parse_arguments "$@"
    
    # 验证参数
    validate_arguments
    
    # 处理视频
    process_video
    
    log "SUCCESS" "转换完成！"
}

# --- 脚本入口 ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi