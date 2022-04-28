require_relative "names"

module Pod
    class PrebuildSandbox < Sandbox

        def self.replace_tagert_copy_source_sh(installer_context)
            standard_sandbox = installer_context.sandbox
            prebuild_sandbox = Pod::PrebuildSandbox.from_standard_sandbox(standard_sandbox)
            list = prebuild_sandbox.exsited_framework_target_names
            installer_context.umbrella_targets.each do |um|
                um.user_targets.each do |target|
                    tn = "Pods-#{target.name}"
                    dir = Pathname.new(File.join(installer_context.sandbox.root,"Target Support Files", tn))
                    sh_path = File.join(dir, "#{tn}-resources.sh")
                    if File.exists?(sh_path)
                        list.each do |tarname|
                            replace_content_file sh_path, tarname
                        end
                    end
                end
            end
        end

        def self.replace_content_file(path, name)
            ostr = "install_resource \"${BUILT_PRODUCTS_DIR}/#{name}"
            nstr = "install_resource \"${PODS_ROOT}/#{name}"
            File.open(path,"r:utf-8") do |lines| #r:utf-8表示以utf-8编码读取文件，要与当前代码文件的编码相同
                buffer = lines.read.gsub(ostr,nstr) #将文件中所有的ostr替换为nstr，并将替换后文件内容赋值给buffer
                File.open(path,"w"){|l| #以写的方式打开文件，将buffer覆盖写入文件
                    l.write(buffer)
                }
            end
        end

        # [String] standard_sandbox_path
        def self.from_standard_sanbox_path(path)
            prebuild_sandbox_path = Pathname.new(path).realpath + "_Prebuild"
            self.new(prebuild_sandbox_path)
        end

        def self.from_standard_sandbox(sandbox)
            self.from_standard_sanbox_path(sandbox.root)
        end

        def standard_sanbox_path
            self.root.parent
        end
        
        def generate_framework_path
            self.root + "GeneratedFrameworks"
        end

        # @param name [String] pass the target.name (may containing platform suffix)
        # @return [Pathname] the folder containing the framework file.
        def framework_folder_path_for_target_name(name)
            self.generate_framework_path + name
        end

        
        def exsited_framework_target_names
            exsited_framework_name_pairs.map {|pair| pair[0]}.uniq
        end
        def exsited_framework_pod_names
            exsited_framework_name_pairs.map {|pair| pair[1]}.uniq
        end
        def existed_target_names_for_pod_name(pod_name)
            exsited_framework_name_pairs.select {|pair| pair[1] == pod_name }.map { |pair| pair[0]}
        end

        def existed_target_version_for_pod_name(pod_name)
            folder = framework_folder_path_for_target_name(pod_name)
            return "" unless folder.exist?
            flag_file_path = folder + "#{pod_name}.pod_name"
            return "" unless flag_file_path.exist?
            version = File.read(flag_file_path)
            version
        end

        def save_pod_name_for_target(target)
            folder = framework_folder_path_for_target_name(target.name)
            return unless folder.exist?
            flag_file_path = folder + "#{target.pod_name}.pod_name"
            File.write(flag_file_path.to_s, "#{target.version}")
        end

        def real_bundle_path_for_pod(path)
            tindex = path.index('/')
            count = path.length - tindex
            temp = path[tindex,count]
            rp = "#{self.root}#{temp}"
            rp
        end

        private

        def pod_name_for_target_folder(target_folder_path)
            name = Pathname.new(target_folder_path).children.find do |child|
                child.to_s.end_with? ".pod_name"
            end
            name = name.basename(".pod_name").to_s unless name.nil?
            name ||= Pathname.new(target_folder_path).basename.to_s # for compatibility with older version
        end

        # Array<[target_name, pod_name]>
        def exsited_framework_name_pairs
            return [] unless generate_framework_path.exist?
            generate_framework_path.children().map do |framework_path|
                if framework_path.directory? && (not framework_path.children.empty?)
                    [framework_path.basename.to_s,  pod_name_for_target_folder(framework_path)]
                else
                    nil
                end
            end.reject(&:nil?).uniq
        end
    end
end

module Pod
    class Sandbox
        # hook 清除pod方法，得到删除的pod，通知主pod更新
        clean_method = instance_method(:clean_pod)
        define_method(:clean_pod) do |pod_name|
            if Pod::is_prebuild_stage
                if Pod::Prebuild::Passer.prebuild_pod_targets_changes.nil?
                    Pod::Prebuild::Passer.prebuild_pod_targets_changes = [pod_name]
                else
                    Pod::Prebuild::Passer.prebuild_pod_targets_changes = (Pod::Prebuild::Passer.prebuild_pod_targets_changes + [pod_name]).uniq
                end
            end
            clean_method.bind(self).(pod_name)
        end
    end
end


