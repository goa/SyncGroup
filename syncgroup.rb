#!/usr/bin/env ruby

require 'xcodeproj'
require 'fileutils'
require 'optparse'

class Output
    def self.colorize(text, color_code)
        "#{color_code}#{text}\033[0m"
    end
    
    def self.errorHeader()
        print(red(bold("Error!\n")))
    end
    
    def self.error(description, value = nil)
        errorHeader()
        print(yellow(description + " "))
        if value != nil then
            print(yellow(bold(value) + "\n\n"))
        end
        exit()
    end
    
    def self.print(text)
        super(text)
    end
    
    def self.red(text); colorize(text, "\033[31m"); end
    def self.green(text); colorize(text, "\033[32m"); end
    def self.yellow(text); colorize(text, "\033[33m"); end
    def self.bold(text); colorize(text, "\033[1m"); end
    def self.underline(text); colorize(text, "\033[4m"); end
end

class SyncGroup
    def initialize(projectName, targetNames, fileFilter, fileSystemPath, projectGroupPath)
        begin
            project = getProject(projectName)
        rescue
            Output.error("Project not found:", projectName)
        end
        
        targets = getTargets(project, targetNames)

        projectGroup = getProjectGroupFromPath(project, projectGroupPath)
        if projectGroup == nil then
            Output.error("Project group not found:", projectGroupPath)
        end
        
        groupFileObjects = getGroupFileObjects(projectGroup, fileFilter)
        
        if !Dir.exist?(fileSystemPath) then
            Output.error("File system path not found:", fileSystemPath)
        end
        
        fileSystemPathWithFilter = File.join(projectGroupPath, fileFilter)
        fileSystemFileNames = Dir[fileSystemPathWithFilter].map { |x| File.basename(x) }
        
        # Add missing files to the project.
        groupFileNames = groupFileObjects.map { |x| x.path }
        filesToAddToProject = fileSystemFileNames - groupFileNames
        addFilesToProject(project, targets, projectGroup, filesToAddToProject)

        Output.print("\n--------------------")
        Output.print("\nAdded " + bold(filesToAddToProject.length.to_s) + " files.")
        
        # Remove project files no longer available in the file system.
        filesToRemoveFromProject = groupFileNames - fileSystemFileNames
        removeFilesFromProject(project, filesToRemoveFromProject)
        
        Output.print("\nRemoved " + bold(filesToRemoveFromProject.length.to_s) + " files.")
        Output.print("\n--------------------\n")
        
        # Save project
        if filesToAddToProject.length > 0 || filesToRemoveFromProject.length > 0 then
            Output.print("\nSaving project...")
            saveProject(project)
        else
            Output.print("\nNo changes were made to the project.\n")
        end
        
        Output.print("\nDone!\n\n")
    end
    
    def getProject(projectName)
        Xcodeproj::Project.open(projectName)
    end
    
    def saveProject(project)
        project.save()
    end
    
    def getTargets(project, targetNames)
        targetNamesArray = targetNames.split(',').map { |x| x.strip() }
        targetsFound = project.targets.find_all { |item|
            targetNamesArray.any? { |s| s.casecmp(item.to_s) == 0 }
        }

        targetsFoundNames = targetsFound.map { |target| target.name }
        targetsNotFound = targetNamesArray.find_all { |requested|
            !targetsFoundNames.any? { |s| s.casecmp(requested.to_s) == 0 }
        }
        
        if targetsNotFound.length > 0 then
            Output.error("Project targets not found:", targetsNotFound)
        end
        
        targetsFound
    end
    
    def addFilesToProject(project, targets, projectGroup, filesToAddToProject)
        filesToAddToProject.each { |fileToAdd|
            fileRef = createFileRef(projectGroup, fileToAdd)
            targets.each { |target|
                sourcesBuildPhase = target.build_phases.find { |x| x.instance_of? Xcodeproj::Project::Object::PBXSourcesBuildPhase }
                addFileRefToPhase(project, fileRef, sourcesBuildPhase)
            }
        }
    end
    
    def removeFilesFromProject(project, filesToRemoveFromProject)
        filesToRemoveFromProject.each { |fileToRemove|
            fileObjectToRemove = project.files.find { |file|
                File.basename(file.path) == fileToRemove
            }
            
            if fileObjectToRemove != nil then
                fileObjectToRemove.remove_from_project()
            end
        }
    end
    
    def getProjectGroupFromPath(project, projectGroupPath)
        project[projectGroupPath]
    end
    
    def getFilesToAdd(fileSystemPath, projectGroupPath)
        filesInDir = Dir[fileSystemPath]
    end
    
    def getGroupFileObjects(group, fileFilter)
        group.children.find_all { |x|
            fileFilterClean = fileFilter.gsub(/\W+/, "")
            x.path.downcase().end_with?(fileFilterClean) }
    end
    
    def createFileRef(group, fileName)
        file_ref = group.new_file(fileName)
        file_ref.path = fileName
        file_ref.source_tree = "<group>"
        
        file_ref
    end
    
    def addFileRefToPhase(project, file_ref, phase)
        build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
        build_file.file_ref = file_ref
        phase.files << build_file
    end
    
    def self.findXcodeProj()
        Dir["*.xcodeproj"].find { |entry| File.directory?(entry) }
    end
end


options = {}
opts = ARGV
OptionParser.new do |opts|
    opts.banner = "Usage: syncgroup.rb [project] [options]"
    opts.separator ""
    opts.separator "Specific options:"
    opts.on("-v", "--[no-]verbose", "Run verbosely") do |v|
        options[:verbose] = v
    end
end.parse!

project = ARGV.pop
if project == nil then
    Output.print "\nYou need to provide the path of the .xcodeproj folder.\n"
    possibleProject = SyncGroup.findXcodeProj()
    if possibleProject != nil
        Output.print("Found " + Output.yellow(possibleProject) + ".\nUse that? (Y/n): ")
        shouldUse = gets
        if shouldUse.downcase != 'y'then
            Output.print("No .xcodeproj folder specified.\n")
        end
    end
end

#SyncGroup.new(
#    project, #    "TalentLMS.xcodeproj",
#    "TalentLMSCorePlatform", # May contain comma-separated target names
#    "*",
#    "Core/TalentLMSCorePlatform/Data/Entities/Generated",
#    "Core/TalentLMSCorePlatform/Data/Entities/Generated"
#)
