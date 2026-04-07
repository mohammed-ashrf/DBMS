#!/bin/bash

function confirm_action() {
    local prompt="$1"

    while true; do
        read -p "$prompt (y/n): " answer
        case "${answer,,}" in
            y|yes)
                return 0
                ;;
            n|no)
                return 1
                ;;
            *)
                echo "Please answer with y or n."
                ;;
        esac
    done
}

function validate_entity_name() {
    local name
    name="$(echo "$1" | xargs)"

    if [[ -z "$name" ]]; then
        echo "Name cannot be empty."
        return 1
    fi

    if [[ ! "$name" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]]; then
        echo "Invalid name. It must start with a letter and contain only letters, numbers, or underscore (_)."
        return 1
    fi

    return 0
}

function normalize_value() {
    echo "$1" | xargs
}

function get_pk_info() {
    local meta_file="$1"
    local pk_col_index=-1
    local pk_col_type=""
    local col_type
    local i=0

    while IFS= read -r line; do
        col_type=$(echo "$line" | cut -d: -f2-)
        if [[ "$col_type" == *:pk ]]; then
            pk_col_index=$i
            pk_col_type=${col_type%%:*}
            break
        fi
        ((i++))
    done < "$meta_file"

    echo "$pk_col_index|$pk_col_type"
}

function sort_data_file_by_pk() {
    local meta_file="$1"
    local data_file="$2"
    local tmp_file="$data_file.tmp"
    local pk_info
    local pk_col_index
    local pk_col_type

    [[ ! -f "$data_file" ]] && return 0
    [[ ! -s "$data_file" ]] && return 0

    pk_info="$(get_pk_info "$meta_file")"
    pk_col_index="${pk_info%%|*}"
    pk_col_type="${pk_info#*|}"

    if [[ "$pk_col_index" -lt 0 ]]; then
        return 0
    fi

    if [[ "$pk_col_type" == "int" || "$pk_col_type" == "float" ]]; then
        LC_ALL=C sort -t'|' -k$((pk_col_index+1)),$((pk_col_index+1)) -n "$data_file" > "$tmp_file" || {
            rm -f "$tmp_file"
            return 1
        }
    else
        LC_ALL=C sort -t'|' -k$((pk_col_index+1)),$((pk_col_index+1)) "$data_file" > "$tmp_file" || {
            rm -f "$tmp_file"
            return 1
        }
    fi

    mv "$tmp_file" "$data_file" || {
        rm -f "$tmp_file"
        return 1
    }

    return 0
}

function table_menu() {
    while true; do
        echo "************* Table Menu ****************"
        echo "1. Create Table"
        echo "2. List Tables"
        echo "3. Drop Table"
        echo "4. Insert Record"
        echo "5. Select Records"
        echo "6. Delete Record"
        echo "7. Update Record"
        echo "8. Back to Main Menu"

        read -p "Choose an option: " choice

        case $choice in
            1) create_table ;;
            2) list_tables ;;
            3) drop_table ;;
            4) insert_record ;;
            5) select_records ;;
            6) delete_record ;;
            7) update_record ;;
            8) break ;;
            *) echo "Invalid option, please try again." ;;
        esac
    done
}

function validate_value_by_type() {
    local value
    local col_type="$2"

    value="$(normalize_value "$1")"

    [[ -z "$value" ]] && return 1

    case "$col_type" in
        int)
            [[ "$value" =~ ^-?[0-9]+$ ]]
            ;;
        float)
            [[ "$value" =~ ^-?([0-9]+([.][0-9]+)?|[.][0-9]+)$ ]]
            ;;
        string)
            return 0
            ;;
        bool|boolean)
            local lower_value="${value,,}"
            [[ "$lower_value" =~ ^(true|false|1|0)$ ]]
            ;;
        *)
            return 1
            ;;
    esac
}

function create_table() {
    read -p "Enter table name: " table_name
    table_name="$(echo "$table_name" | xargs)"

    if ! validate_entity_name "$table_name"; then
        return
    fi

    meta_file="$current_db/$table_name.meta"
    data_file="$current_db/$table_name.data"

    if [ -f "$meta_file" ]; then
        echo "Table already exists."
        return
    fi

    while true; do
        read -p "Enter Number of columns: " num_cols
        num_cols="$(normalize_value "$num_cols")"

        if [[ "$num_cols" =~ ^[1-9][0-9]*$ ]]; then
            break
        fi

        echo "Invalid number of columns. Please enter a positive integer."
    done

    has_primary_key=0
    column_defs=()
    seen_column_names="|"

    for ((i=1; i<=num_cols; i++)); do
        read -p "Enter column $i name: " col_name
        col_name="$(normalize_value "$col_name")"

        if ! validate_entity_name "$col_name"; then
            return
        fi

        if [[ "$seen_column_names" == *"|$col_name|"* ]]; then
            echo "Duplicate column name '$col_name' is not allowed."
            return
        fi
        seen_column_names+="$col_name|"

        read -p "Enter column $i type (string/int/float/bool): " col_type
        col_type=$(echo "$col_type" | tr '[:upper:]' '[:lower:]')
        col_type="$(normalize_value "$col_type")"

        if [[ "$col_type" == "boolean" ]]; then
            col_type="bool"
        fi

        if [[ "$col_type" != "string" && "$col_type" != "int" && "$col_type" != "float" && "$col_type" != "bool" ]]; then
            echo "Invalid column type. Please enter 'string', 'int', 'float', or 'bool'."
            return
        fi

        while true; do
            read -p "Is this column a primary key? (y/n): " is_pk
            is_pk="$(normalize_value "$is_pk")"
            is_pk="${is_pk,,}"

            if [[ "$is_pk" == "y" || "$is_pk" == "yes" ]]; then
                if [[ "$has_primary_key" -eq 1 ]]; then
                    echo "Only one primary key is allowed per table."
                    continue
                fi
                col_type="$col_type:pk"
                has_primary_key=1
                break
            elif [[ "$is_pk" == "n" || "$is_pk" == "no" ]]; then
                break
            else
                echo "Please answer with y or n."
            fi
        done

        column_defs+=("$col_name:$col_type")
    done

    if [[ "$has_primary_key" -ne 1 ]]; then
        echo "Table must have exactly one primary key column."
        return
    fi

    > "$meta_file"
    for def in "${column_defs[@]}"; do
        echo "$def" >> "$meta_file"
    done

    touch "$data_file" # Create data file
    echo "Table '$table_name' created successfully."
    if [[ $has_primary_key -eq 1 ]]; then
        echo "Note: Primary key values must be UNIQUE and NOT NULL (cannot be empty)."
    fi
}

function list_tables() {
    echo "Available Tables:"
    tables=$(find "$current_db" -mindepth 1 -maxdepth 1 -type f -name '*.meta' -exec basename {} .meta \; | sort)
    if [[ -z "$tables" ]]; then
        echo "(none)"
        return
    fi
    echo "$tables"
}

function drop_table() {
    read -p "Enter table name to drop: " table_name
    table_name="$(echo "$table_name" | xargs)"

    if ! validate_entity_name "$table_name"; then
        return
    fi

    meta_file="$current_db/$table_name.meta"
    data_file="$current_db/$table_name.data"

    if [ -f "$meta_file" ]; then
        if ! confirm_action "Are you sure you want to drop table '$table_name'?"; then
            echo "Drop table canceled."
            return
        fi
        rm -f "$meta_file" "$data_file"
        echo "Table '$table_name' dropped successfully."
    else
        echo "Table does not exist."
    fi
}


function insert_record() {
    read -p "Enter table name to insert into: " table_name
    table_name="$(echo "$table_name" | xargs)"

    if ! validate_entity_name "$table_name"; then
        return
    fi

    meta_file="$current_db/$table_name.meta"
    data_file="$current_db/$table_name.data"

    if [ ! -f "$meta_file" ]; then
        echo "Table does not exist."
        return
    fi

    while true; do
        record_values=()
        pk_info="$(get_pk_info "$meta_file")"
        pk_col_index="${pk_info%%|*}"
        col_index=0

        exec 3< "$meta_file"
        while IFS= read -r line <&3; do
            col_name=$(echo "$line" | cut -d: -f1)
            col_type=$(echo "$line" | cut -d: -f2-)
            base_col_type=${col_type%%:*}

            while true; do
                read -p "Enter value for $col_name ($base_col_type) [or :back to cancel]: " value

                if [[ "$value" == ":back" ]]; then
                    exec 3<&-
                    echo "Insert canceled."
                    return
                fi

                normalized_value="$(normalize_value "$value")"

                if [[ "$base_col_type" == "string" && "$normalized_value" == *"|"* ]]; then
                    echo "Invalid input. Character '|' is not allowed in string values."
                    continue
                fi

                if validate_value_by_type "$normalized_value" "$base_col_type"; then
                    break
                fi

                if [[ "$col_type" == *:pk ]]; then
                    echo "Primary key cannot be empty and must be $base_col_type."
                elif [[ "$base_col_type" == "int" ]]; then
                    echo "Invalid input. Expected an integer."
                elif [[ "$base_col_type" == "float" ]]; then
                    echo "Invalid input. Expected a float."
                elif [[ "$base_col_type" == "bool" || "$base_col_type" == "boolean" ]]; then
                    echo "Invalid input. Expected a boolean (true/false/1/0)."
                else
                    echo "Invalid input for type '$base_col_type'."
                fi
            done

            record_values+=("$normalized_value")
            ((col_index++))
        done
        exec 3<&-

        # Enforce primary key uniqueness constraint
        if [[ "$pk_col_index" -ge 0 ]]; then
            pk_value="${record_values[$pk_col_index]}"
            if awk -F'|' -v pk_index=$((pk_col_index+1)) -v pk_value="$pk_value" \
             'function trim(s){gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s} trim($pk_index) == pk_value { found=1; exit } END { exit !found }' "$data_file"; then
                echo "Error: Primary key value '$pk_value' already exists. Record not inserted."
                continue
            fi
        fi

        record=""
        for value in "${record_values[@]}"; do
            record+="$value|"
        done

        record=${record%|}  # Remove trailing|

        echo "$record" >> "$data_file"

        if ! sort_data_file_by_pk "$meta_file" "$data_file"; then
            echo "Warning: Record inserted, but failed to reorder data by primary key."
            return
        fi

        echo "Record inserted successfully."

        read -p "Do you want to insert another record in the same table? (y/n): " insert_another
        if [[ ! "$insert_another" =~ ^[Yy]$ ]]; then
            break
        fi
    done
}

function select_records() {
    read -p "Enter table name to select from: " table_name
    table_name="$(echo "$table_name" | xargs)"

    if ! validate_entity_name "$table_name"; then
        return
    fi

    meta_file="$current_db/$table_name.meta"
    data_file="$current_db/$table_name.data"

    if [ ! -f "$meta_file" ]; then
        echo "Table does not exist."
        return
    fi

    if [ ! -s "$data_file" ]; then
        echo "No records found."
        return
    fi

    # Print column headers
    headers=""
    while IFS= read -r line; do
        col_name=$(echo "$line" | cut -d: -f1)
        headers+="$col_name | "
    done < "$meta_file"
    headers=${headers% | } # Remove trailing |
    echo "$headers"
    echo "-------------------------"

    # Print records (ordered by PK when available)
    pk_info="$(get_pk_info "$meta_file")"
    pk_col_index="${pk_info%%|*}"
    pk_col_type="${pk_info#*|}"

    if [[ "$pk_col_index" -ge 0 ]]; then
        if [[ "$pk_col_type" == "int" || "$pk_col_type" == "float" ]]; then
            LC_ALL=C sort -t'|' -k$((pk_col_index+1)),$((pk_col_index+1)) -n "$data_file" | while IFS= read -r record; do
                echo "$record" | tr '|' ' '
            done
        else
            LC_ALL=C sort -t'|' -k$((pk_col_index+1)),$((pk_col_index+1)) "$data_file" | while IFS= read -r record; do
                echo "$record" | tr '|' ' '
            done
        fi
    else
        while IFS= read -r record; do
            echo "$record" | tr '|' ' '
        done < "$data_file"
    fi
}


function delete_record() {
    read -p "Enter table name to delete from: " table_name
    table_name="$(echo "$table_name" | xargs)"

    if ! validate_entity_name "$table_name"; then
        return
    fi

    meta_file="$current_db/$table_name.meta"
    data_file="$current_db/$table_name.data"

    if [ ! -f "$meta_file" ]; then
        echo "Table does not exist."
        return
    fi

    if [ ! -s "$data_file" ]; then
        echo "No records found."
        return
    fi

    read -p "Enter primary key value to delete: " pk_value
    pk_value="$(normalize_value "$pk_value")"

    # Get PK column index and type
    pk_info="$(get_pk_info "$meta_file")"
    pk_col_index="${pk_info%%|*}"
    pk_col_type="${pk_info#*|}"

    if [ $pk_col_index -eq -1 ]; then
        echo "No primary key defined for this table."
        return
    fi

    if ! validate_value_by_type "$pk_value" "$pk_col_type"; then
        echo "Invalid primary key value. Expected $pk_col_type."
        return
    fi

    target_line_number=$(awk -F'|' -v pk_index=$((pk_col_index+1)) -v pk_value="$pk_value" 'function trim(s){gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s} trim($pk_index) == pk_value { print NR; exit }' "$data_file")

    if [[ -z "$target_line_number" ]]; then
        echo "No record found with that primary key."
        return
    fi

    if ! confirm_action "Are you sure you want to delete record with primary key '$pk_value' from table '$table_name'?"; then
        echo "Delete record canceled."
        return
    fi

    # Delete record with matching PK value
    awk -F'|' -v pk_index=$((pk_col_index+1)) -v pk_value="$pk_value" 'function trim(s){gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s} trim($pk_index) != pk_value' "$data_file" > "$data_file.tmp" && mv "$data_file.tmp" "$data_file"
    echo "Record deleted successfully."
}


function update_record() {
    read -p "Enter table name to update: " table_name
    table_name="$(echo "$table_name" | xargs)"

    if ! validate_entity_name "$table_name"; then
        return
    fi

    meta_file="$current_db/$table_name.meta"
    data_file="$current_db/$table_name.data"

    if [ ! -f "$meta_file" ]; then
        echo "Table does not exist."
        return
    fi

    if [ ! -s "$data_file" ]; then
        echo "No records found."
        return
    fi

    # Get column metadata and PK index
    pk_info="$(get_pk_info "$meta_file")"
    pk_col_index="${pk_info%%|*}"
    col_names=()
    col_types=()
    i=0
    while IFS= read -r line; do
        col_name=$(echo "$line" | cut -d: -f1)
        col_type=$(echo "$line" | cut -d: -f2-)
        base_col_type=${col_type%%:*}
        col_names+=("$col_name")
        col_types+=("$base_col_type")
        ((i++))
    done < "$meta_file"

    if [ $pk_col_index -eq -1 ]; then
        echo "No primary key defined for this table."
        return
    fi

    pk_col_type="${col_types[$pk_col_index]}"

    while true; do
        read -p "Enter primary key value of the row to update (or :back to cancel): " pk_value

        if [[ "$pk_value" == ":back" ]]; then
            echo "Update canceled."
            return
        fi

        pk_value="$(normalize_value "$pk_value")"

        if ! validate_value_by_type "$pk_value" "$pk_col_type"; then
            echo "Error: Primary key cannot be empty and must be $pk_col_type."
            continue
        fi

        target_line_number=$(awk -F'|' -v pk_index=$((pk_col_index+1)) -v pk_value="$pk_value" 'function trim(s){gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s} trim($pk_index) == pk_value { print NR; exit }' "$data_file")
        if [[ -n "$target_line_number" ]]; then
            break
        fi

        echo "No record found with that primary key. Try again or type :back to cancel."
    done

    current_record=$(sed -n "${target_line_number}p" "$data_file")
    IFS='|' read -r -a record_values <<< "$current_record"

    echo "Current record to update:"
    for ((i=0; i<${#col_names[@]}; i++)); do
        echo "${col_names[$i]}: ${record_values[$i]}"
    done
    echo "-------------------------"

    echo "Choose a column to update:"
    for ((i=0; i<${#col_names[@]}; i++)); do
        col_label="${col_names[$i]} (${col_types[$i]})"
        if [[ $i -eq $pk_col_index ]]; then
            col_label+=" [PK]"
        fi
        echo "$((i+1)). $col_label"
    done

    while true; do
        read -p "Enter column number to update (or :back to cancel): " col_choice

        if [[ "$col_choice" == ":back" ]]; then
            echo "Update canceled."
            return
        fi

        if [[ "$col_choice" =~ ^[0-9]+$ ]] && [ "$col_choice" -ge 1 ] && [ "$col_choice" -le "${#col_names[@]}" ]; then
            selected_col_index=$((col_choice-1))
            break
        fi

        echo "Invalid column choice. Please enter a valid number."
    done

    selected_col_name="${col_names[$selected_col_index]}"
    selected_col_type="${col_types[$selected_col_index]}"
    selected_current_value="${record_values[$selected_col_index]}"

    while true; do
        read -p "Enter new value for $selected_col_name ($selected_col_type) [current: $selected_current_value, :back=cancel]: " new_value

        if [[ "$new_value" == ":back" ]]; then
            echo "Update canceled."
            return
        fi

        new_value="$(normalize_value "$new_value")"

        if [[ "$selected_col_type" == "string" && "$new_value" == *"|"* ]]; then
            echo "Invalid input. Character '|' is not allowed in string values."
            continue
        fi

        if ! validate_value_by_type "$new_value" "$selected_col_type"; then
            if [[ "$selected_col_type" == "int" ]]; then
                echo "Invalid input. Expected an integer."
            elif [[ "$selected_col_type" == "float" ]]; then
                echo "Invalid input. Expected a float."
            elif [[ "$selected_col_type" == "bool" || "$selected_col_type" == "boolean" ]]; then
                echo "Invalid input. Expected a boolean (true/false/1/0)."
            else
                echo "Invalid input for type '$selected_col_type'."
            fi
            continue
        fi

        # Enforce primary key uniqueness when updating PK column
        if [[ $selected_col_index -eq $pk_col_index ]]; then
            if awk -F'|' -v target="$target_line_number" -v pk_index=$((pk_col_index+1)) -v pk_value="$new_value" 'function trim(s){gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s} NR != target && trim($pk_index) == pk_value { found=1; exit } END { exit !found }' "$data_file"; then
                echo "Error: Primary key value '$new_value' already exists. Please enter a different value."
                continue
            fi
        fi

        record_values[$selected_col_index]="$new_value"
        break
    done

    updated_record=""
    for value in "${record_values[@]}"; do
        updated_record+="$value|"
    done
    updated_record=${updated_record%|}

    awk -v target="$target_line_number" -v new_record="$updated_record" 'NR==target { $0=new_record } { print }' "$data_file" > "$data_file.tmp" && mv "$data_file.tmp" "$data_file"

    if ! sort_data_file_by_pk "$meta_file" "$data_file"; then
        echo "Warning: Record updated, but failed to reorder data by primary key."
        return
    fi

    echo "Record updated successfully."
}
