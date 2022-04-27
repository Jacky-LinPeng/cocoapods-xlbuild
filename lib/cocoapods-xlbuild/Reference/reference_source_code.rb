
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

	    		project = Xcodeproj::Project.open(proj_path)
    			exsited_framework_pod_names.each do |target_name|
	    			real_reference("_Prebuild/#{target_name}", project, target_name)
	    		end
	    		project.save;
	    	end


				# 动态库dsym问题[CP] Copy dSYM
				def adjust_dynamic_framework_dsym
					sandbox_path = Pathname.new(sandbox.root).to_s
					pre_sandbox = Pod::PrebuildSandbox.from_standard_sandbox(sandbox)
					exsited_framework_pod_names = pre_sandbox.exsited_framework_pod_names || []

					exsited_framework_pod_names.each do |target_name|
						input_xcfilelist = sandbox_path + "/Target Support Files/" + target_name + "/#{target_name}-copy-dsyms-input-files.xcfilelist"
						output_xcfilelist = sandbox_path + "/Target Support Files/" + target_name + "/#{target_name}-copy-dsyms-output-files.xcfilelist"
						remove_duplicated_bcsymbolmap_lines(input_xcfilelist)
						remove_duplicated_bcsymbolmap_lines(output_xcfilelist)
					end
				end

				#https://github.com/CocoaPods/CocoaPods/issues/10373
				def remove_duplicated_bcsymbolmap_lines(path)
					if File.exist?path
						top_lines = []
						bcsymbolmap_lines = []
						for line in File.readlines(path).map { |line| line.strip }
							if line.include? ".bcsymbolmap"
								bcsymbolmap_lines.append(line)
							else
								#去重
								if not top_lines.include?line
									top_lines.append(line)
								end
							end
						end

						final_lines = top_lines + bcsymbolmap_lines.uniq
						File.open(path, "w+") do |f|
							f.puts(final_lines)
						end
					end
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



