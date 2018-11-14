#! /usr/bin/awk -f

function print_key_val(key, val)
{
	if (!is_printed) {
		if (length(val) != 0)
			print key, val
		is_printed = 1
	}
}

BEGIN {
#	FS = "="
#	OFS = " = "
	current_section = ""
	is_printed = 0
	is_section_found = 0
}

# Skip comments
/^[ \t]*#/ {print $0; next}
/^[ \t]*;/ {print $0; next}

# Trim key and value. Values of $1 and $2 will be replaced
{
	gsub(/^ [ \t]+/, "", $1); gsub(/[ \t]+$/, "", $1);
	gsub(/^ [ \t]+/, "", $2); gsub(/[ \t]+$/, "", $2);
}

# Get current section
/^[ \t]*\[.*\]/ {
        if (current_section ~ section && !is_printed) {
		# Leaving our section, add the key
		print_key_val(key, value)
	}

	current_section = $1

	if (current_section ~ section)
		is_section_found = 1

}

# Skip other sections
current_section !~ section {print $0; next}

# Skip other keys
$1 != key { print $0; next}

# Update our key
$1 == key {
	print_key_val(key, value)
	next
}

END {
	if (length(value) != 0 && !is_printed) {
		if (!is_section_found) {
			print "["section"]"
		}

		print_key_val(key, value)
	}
}
