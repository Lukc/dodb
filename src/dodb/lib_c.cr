
lib LibC
	{% if flag?(:linux) %}
		O_EXCL = 0o200
	{% elsif flag?(:openbsd) %}
		O_EXCL = 0x0800
	{% end %}
end

