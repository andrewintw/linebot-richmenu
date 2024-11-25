#!/bin/sh

# LINE Channel Access Token
ACCESS_TOKEN="<CHANNEL_ACCESS_TOKEN>"

# API Endpoints
API_BASE="https://api.line.me/v2/bot/richmenu"
API_DATA_BASE="https://api-data.line.me/v2/bot/richmenu"
API_USER_ALL="${API_BASE/richmenu/user/all/richmenu}"

# 顯示使用方法
show_usage() {
	local cmd=$(basename $0)
	cat << EOF
Usage:
	$cmd list                         - 列出所有 Rich Menu
	$cmd create <menu.json>           - 根據 JSON 檔案建立 Rich Menu
	$cmd info <richMenuId>            - 查看特定 Rich Menu 的詳細資訊
	$cmd validate <menu.json>         - 驗證 Rich Menu 設定檔
	$cmd upload-image <richMenuId> <image_path> - 上傳 Rich Menu 圖片
	$cmd default <richMenuId>         - 設定預設 Rich Menu
	$cmd check-image <richMenuId>     - 檢查 Rich Menu 是否有圖片
	$cmd check-default                - 檢查目前的預設 Rich Menu
	$cmd delete <richMenuId>          - 刪除指定的 Rich Menu
	$cmd clear-default                - 清除預設的 Rich Menu
EOF
}

# 檢查 Rich Menu 圖片狀態的內部函數
_check_richmenu_image_status() {
	local menu_id="$1"
	local image_status=$(curl -s -I -X GET "${API_DATA_BASE}/${menu_id}/content" \
		-H "Authorization: Bearer ${ACCESS_TOKEN}" | grep "HTTP" | awk '{print $2}')
	
	if [ "$image_status" = "200" ]; then
		return 0  # 有圖片
	else
		return 1  # 無圖片
	fi
}

# 列出所有 Rich Menu
list_richmenus() {
	echo "取得 Rich Menu 列表..."
	local response=$(curl -s -X GET "${API_BASE}/list" -H "Authorization: Bearer ${ACCESS_TOKEN}")
	
	# 取得預設選單 ID
	local default_menu_id=$(curl -s -X GET "https://api.line.me/v2/bot/user/all/richmenu" \
		-H "Authorization: Bearer ${ACCESS_TOKEN}" | jq -r '.richMenuId // empty')
	
	# 使用 jq 解析 JSON 並計算數量
	local count=$(echo "$response" | jq '.richmenus | length')
	echo "找到 $count 個 Rich Menu："
	
	# 使用 jq 遍歷每個 menu
	echo "$response" | jq -r '.richmenus[] | "------------------------\nID:        \(.richMenuId)\n名稱:      \(.name)" as $header | $header' | while read -r line; do
		if [[ $line == "ID: "* ]]; then
			# 取得 Rich Menu ID
			local menu_id=${line#"ID:        "}
			echo "$line"
		else
			echo "$line"
		fi
		
		# 檢查圖片狀態
		if [[ $line == "名稱: "* ]]; then
			_check_richmenu_image_status "$menu_id"
			if [ $? -eq 0 ]; then
				echo "圖片狀態:  已上傳"
			else
				echo "圖片狀態:  未上傳"
			fi
			
			# 檢查是否為預設選單
			if [ "$menu_id" = "$default_menu_id" ]; then
				echo "預設選單:  是"
			else
				echo "預設選單:  否"
			fi
			
			# 顯示按鈕資訊
			echo "按鈕:"
			echo "$response" | jq -r --arg id "$menu_id" '.richmenus[] | select(.richMenuId == $id) | .areas[] | "  \((.bounds.y/843 * 3 + .bounds.x/833 + 1)|floor). \(.action.text) (\(.action.type))"'
		fi
	done
	echo "------------------------"
}

# 驗證 Rich Menu 設定
validate_richmenu() {
	local json_file="$1"
	if [ ! -f "$json_file" ]; then
		echo "錯誤: 找不到檔案 $json_file"
		exit 1
	fi

	echo "驗證 Rich Menu 設定..."
	local response=$(curl -s -X POST "${API_BASE}/validate" \
		-H "Authorization: Bearer ${ACCESS_TOKEN}" \
		-H "Content-Type: application/json" \
		-d @"$json_file")

	if [ "$response" = "{}" ]; then
		echo "驗證成功！"
		return 0
	else
		echo "驗證失敗："
		
		# 檢查是否有詳細錯誤資訊
		local has_details=$(echo "$response" | jq 'has("details")')
		if [ "$has_details" = "true" ]; then
			echo "$response" | jq -r '.message'
			echo "詳細錯誤："
			echo "$response" | jq -r '.details[] | "- \(.property): \(.message)"'
		else
			local error_message=$(echo "$response" | jq -r '.message // "未知錯誤"')
			echo "錯誤訊息: $error_message"
		fi
		return 1
	fi
}

# 建立新的 Rich Menu
create_richmenu() {
	local json_file="$1"
	if [ ! -f "$json_file" ]; then
		echo "錯誤: 找不到檔案 $json_file"
		exit 1
	fi

	# 先進行驗證
	echo "先驗證 Rich Menu 設定..."
	if ! validate_richmenu "$json_file"; then
		echo "建立失敗：設定檔驗證未通過"
		exit 1
	fi

	echo "建立 Rich Menu..."
	local response=$(curl -s -X POST "${API_BASE}" \
		-H "Authorization: Bearer ${ACCESS_TOKEN}" \
		-H "Content-Type: application/json" \
		-d @"$json_file")

	# 檢查是否包含 richMenuId
	local menu_id=$(echo "$response" | jq -r '.richMenuId')
	if [ "$menu_id" != "null" ] && [ ! -z "$menu_id" ]; then
		echo "建立成功！"
		echo "Rich Menu ID: $menu_id"
		echo "提醒：別忘了上傳圖片："
		echo "./richmenu_ctrl.sh upload-image $menu_id <image_path>"
	else
		echo "建立失敗："
		
		# 檢查是否有詳細錯誤資訊
		local has_details=$(echo "$response" | jq 'has("details")')
		if [ "$has_details" = "true" ]; then
			echo "$response" | jq -r '.message'
			echo "詳細錯誤："
			echo "$response" | jq -r '.details[] | "- \(.property): \(.message)"'
		else
			local error_message=$(echo "$response" | jq -r '.message // "未知錯誤"')
			echo "錯誤訊息: $error_message"
		fi
		exit 1
	fi
}

# 查看特定 Rich Menu 的資訊
get_richmenu_info() {
	local menu_id="$1"
	if [ -z "$menu_id" ]; then
		echo "錯誤: 需要提供 Rich Menu ID"
		exit 1
	fi

	echo "取得 Rich Menu 資訊..."
	local response=$(curl -s -X GET "${API_BASE}/$menu_id" \
		-H "Authorization: Bearer ${ACCESS_TOKEN}")
	
	# 檢查是否包含 richMenuId
	local rich_menu_id=$(echo "$response" | jq -r '.richMenuId')
	if [ "$rich_menu_id" != "null" ] && [ ! -z "$rich_menu_id" ]; then
		echo "$response" | jq '.'
	else
		local error_message=$(echo "$response" | jq -r '.message // "未知錯誤"')
		echo "取得失敗："
		echo "錯誤訊息: $error_message"
		exit 1
	fi
}

# 上傳 Rich Menu 圖片
upload_richmenu_image() {
	local menu_id="$1"
	local image_path="$2"

	if [ -z "$menu_id" ]; then
		echo "錯誤: 需要提供 Rich Menu ID"
		exit 1
	fi

	if [ ! -f "$image_path" ]; then
		echo "錯誤: 找不到圖片檔案 $image_path"
		exit 1
	fi

	# 檢查檔案類型
	local mime_type=$(file -b --mime-type "$image_path")
	if [ "$mime_type" != "image/jpeg" ] && [ "$mime_type" != "image/png" ]; then
		echo "錯誤: 圖片必須是 JPEG 或 PNG 格式"
		exit 1
	fi

	echo "上傳 Rich Menu 圖片..."
	local response=$(curl -s -X POST "${API_DATA_BASE}/${menu_id}/content" \
		-H "Authorization: Bearer ${ACCESS_TOKEN}" \
		-H "Content-Type: ${mime_type}" \
		--upload-file "${image_path}")

	if [ "$response" = "{}" ]; then
		echo "上傳成功！"
	else
		# 解析錯誤訊息
		local error_message=$(echo "$response" | jq -r '.message // "未知錯誤"')
		echo "上傳失敗："
		echo "錯誤訊息: $error_message"
		exit 1
	fi
}

# 設定預設 Rich Menu
set_default_richmenu() {
	local menu_id="$1"
	if [ -z "$menu_id" ]; then
		echo "錯誤: 需要提供 Rich Menu ID"
		exit 1
	fi

	echo "設定預設 Rich Menu..."
	local response=$(curl -s -X POST "https://api.line.me/v2/bot/user/all/richmenu/${menu_id}" \
		-H "Authorization: Bearer ${ACCESS_TOKEN}" \
		-H "Content-Length: 0")

	# 如果回應是空的 JSON 物件 "{}"，表示成功
	if [ "$response" = "{}" ]; then
		echo "設定成功！"
	else
		# 解析錯誤訊息
		local error_message=$(echo "$response" | jq -r '.message // "未知錯誤"')
		echo "設定失敗："
		echo "錯誤訊息: $error_message"
		exit 1
	fi
}

# 檢查 Rich Menu 圖片
check_richmenu_image() {
	local menu_id="$1"
	if [ -z "$menu_id" ]; then
		echo "錯誤: 需要提供 Rich Menu ID"
		exit 1
	fi

	echo "檢查 Rich Menu 圖片..."
	_check_richmenu_image_status "$menu_id"
	if [ $? -eq 0 ]; then
		echo "圖片狀態: 已上傳"
	else
		echo "圖片狀態: 未上傳"
	fi
}

# 檢查預設 Rich Menu
check_default_richmenu() {
	echo "檢查預設 Rich Menu..."
	local response=$(curl -s -X GET "https://api.line.me/v2/bot/user/all/richmenu" \
		-H "Authorization: Bearer ${ACCESS_TOKEN}")
	
	if [ -z "$response" ]; then
		echo "目前沒有設定預設選單"
	else
		local menu_id=$(echo "$response" | jq -r '.richMenuId')
		echo "目前的預設選單 ID: $menu_id"
		
		# 取得選單詳細資訊
		local menu_info=$(curl -s -X GET "${API_BASE}/${menu_id}" \
			-H "Authorization: Bearer ${ACCESS_TOKEN}")
		echo "選單名稱: $(echo "$menu_info" | jq -r '.name')"
	fi
}

# 刪除 Rich Menu
delete_richmenu() {
	local menu_id="$1"
	if [ -z "$menu_id" ]; then
		echo "錯誤: 需要提供 Rich Menu ID"
		exit 1
	fi

	echo "刪除 Rich Menu..."
	local response=$(curl -s -X DELETE "${API_BASE}/${menu_id}" \
		-H "Authorization: Bearer ${ACCESS_TOKEN}")

	if [ "$response" = "{}" ]; then
		echo "刪除成功！"
	else
		local error_message=$(echo "$response" | jq -r '.message')
		echo "刪除失敗："
		echo "錯誤訊息: $error_message"
		exit 1
	fi
}

# 清除預設 Rich Menu
clear_default_richmenu() {
	echo "清除預設 Rich Menu..."
	local response=$(curl -s -X DELETE "${API_USER_ALL}" \
		-H "Authorization: Bearer ${ACCESS_TOKEN}")

	if [ "$response" = "{}" ]; then
		echo "預設 Rich Menu 已清除！"
	else
		local error_message=$(echo "$response" | jq -r '.message // "未知錯誤"')
		echo "清除失敗："
		echo "錯誤訊息: $error_message"
		exit 1
	fi
}

# 主程式
case "$1" in
	"list")
		list_richmenus
		;;
	"create")
		if [ -z "$2" ]; then
			echo "錯誤: 需要提供 JSON 檔案"
			show_usage
			exit 1
		fi
		create_richmenu "$2"
		;;
	"info")
		if [ -z "$2" ]; then
			echo "錯誤: 需要提供 Rich Menu ID"
			show_usage
			exit 1
		fi
		get_richmenu_info "$2"
		;;
	"validate")
		if [ -z "$2" ]; then
			echo "錯誤: 需要提供 JSON 檔案"
			show_usage
			exit 1
		fi
		validate_richmenu "$2"
		;;
	"upload-image")
		if [ -z "$2" ] || [ -z "$3" ]; then
			echo "錯誤: 需要提供 Rich Menu ID 和圖片路徑"
			show_usage
			exit 1
		fi
		upload_richmenu_image "$2" "$3"
		;;
	"default")
		if [ -z "$2" ]; then
			echo "錯誤: 需要提供 Rich Menu ID"
			show_usage
			exit 1
		fi
		set_default_richmenu "$2"
		;;
	"check-image")
		if [ -z "$2" ]; then
			echo "錯誤: 需要提供 Rich Menu ID"
			show_usage
			exit 1
		fi
		check_richmenu_image "$2"
		;;
	"check-default")
		check_default_richmenu
		;;
	"delete")
		if [ -z "$2" ]; then
			echo "錯誤: 需要提供 Rich Menu ID"
			show_usage
			exit 1
		fi
		delete_richmenu "$2"
		;;
	"clear-default")
		clear_default_richmenu
		;;
	*)
		show_usage
		exit 1
		;;
esac 
