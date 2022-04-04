
require 'xcodeproj'
require_relative '../helper/passer'
require_relative '../helper/prebuild_sandbox'

module Pod
    class Installer
    	class PostInstallHooksContext
	    	# 将源码引入主工程，方便源码调试
	    	def refrence_source_code
	    		sandbox_path = Pathname.new(sandbox.root)
	    		pre_sandbox = Pod::PrebuildSandbox.from_standard_sandbox(sandbox)

	    		exsited_framework_pod_names = pre_sandbox.exsited_framework_pod_names || []
	    		proj_path = sandbox_path + get_project_name("Pods")

					proj_path_new = Pathname.new(sandbox.project_path)

					puts "[HY].沙盒路径：#{sandbox_path}"
	    		project = Xcodeproj::Project.open(proj_path)
    			exsited_framework_pod_names.each do |target_name|
	    			real_reference("_Prebuild/#{target_name}", project, target_name)
	    		end
	    		project.save;
	    	end

	    	private
	    	def get_project_name(tageter_name)
	    		return "#{tageter_name}.xcodeproj"
	    	end

	    	def real_reference(file_path, project, target_name)
				group = project.main_group.find_subpath(File.join("SourceCode", target_name), true)
				group.set_source_tree('SOURCE_ROOT')
				group.set_path(file_path)
			    add_files_to_group(group)
	    	end

	    	#添加文件链接
			def add_files_to_group(group)
			  Dir.foreach(group.real_path) do |entry|
			    filePath = File.join(group.real_path, entry)
			    # 过滤目录和.DS_Store文件
			    if entry != ".DS_Store" && !filePath.to_s.end_with?(".meta") &&entry != "." &&entry != ".." then
			    	# 向group中增加文件引用
					group.new_reference(filePath)
				end
			  end
			end
	    end
	end
end



