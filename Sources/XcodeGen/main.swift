import Commander
import Foundation
import JSONUtilities
import PathKit
import ProjectSpec
import XcodeGenKit
import xcproj
import Yams

let version = try Version("1.11.2")

func generate(spec: String, project: String, lockfile: String, isQuiet: Bool, justVersion: Bool) {
    if justVersion {
        print(version)
        exit(EXIT_SUCCESS)
    }

    let logger = Logger(isQuiet: isQuiet)

    func fatalError(_ message: String) -> Never {
        logger.error(message)
        exit(1)
    }

    let projectSpecPath = Path(spec).absolute()
    let projectPath = project == "" ? projectSpecPath.parent() : Path(project).absolute()

    if !projectSpecPath.exists {
        fatalError("No project spec found at \(projectSpecPath.absolute())")
    }

    let projectDictionary: JSONDictionary
    let project: Project
    do {
        projectDictionary = try Project.loadDictionary(path: projectSpecPath)
        project = try Project(basePath: projectSpecPath.parent(), jsonDictionary: projectDictionary)
        logger.info("📋  Loaded project:\n  \(project.debugDescription.replacingOccurrences(of: "\n", with: "\n  "))")
    } catch let error as CustomStringConvertible {
        fatalError("Parsing project spec failed: \(error)")
    } catch {
        fatalError("Parsing project spec failed: \(error.localizedDescription)")
    }

    // Lock file
    var lockFileContent: String = ""
    let lockFilePath = lockfile.isEmpty ? nil : Path(lockfile)
    if let lockFilePath = lockFilePath {

        let files = Array(Set(project.allFiles))
            .map { $0.byRemovingBase(path: project.basePath).string }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .joined(separator: "\n")

        let spec: String
        do {
            let node = try Node(projectDictionary)
            spec = try Yams.serialize(node: node)
        } catch {
            fatalError("Couldn't serialize spec for lockfile")
        }

        lockFileContent = """
        # XCODEGEN VERSION
        \(version)

        # SPEC
        \(spec)

        # FILES
        \(files)"

        """
        if lockFilePath.exists {
            do {
                let lockFile: String = try lockFilePath.read()
                let oldFiles = lockFile

                if oldFiles == lockFileContent {
                    logger.info("✅  Not generating project as lockfile \(lockFilePath) has not changed")
                    return
                }
            } catch {
                fatalError("Couldn't load \(lockFilePath)")
            }
        }
    }

    do {
        logger.info("⚙️  Generating project...")

        try project.validateMinimumXcodeGenVersion(version)

        let projectGenerator = ProjectGenerator(project: project)
        let xcodeProject = try projectGenerator.generateXcodeProject()

        logger.info("⚙️  Writing project...")

        let projectFile = projectPath + "\(project.name).xcodeproj"
        let tempPath = Path.temporary + "XcodeGen_\(Int(NSTimeIntervalSince1970))"
        try? tempPath.delete()
        if projectFile.exists {
            try projectFile.copy(tempPath)
        }
        try xcodeProject.write(path: tempPath, override: true)
        try? projectFile.delete()
        try tempPath.copy(projectFile)
        try? tempPath.delete()

        if let lockFilePath = lockFilePath {
            try lockFilePath.write(lockFileContent)
            logger.success("💾  Wrote lockfile to \(lockFilePath)")
        }
        logger.success("💾  Saved project to \(projectFile.string)")
    } catch let error as SpecValidationError {
        fatalError(error.description)
    } catch {
        fatalError("Generation failed: \(error.localizedDescription)")
    }
}

command(
    Option<String>(
        "spec",
        default: "project.yml",
        flag: "s",
        description: "The path to the project spec file"
    ),
    Option<String>(
        "project",
        default: "",
        flag: "p",
        description: "The path to the folder where the project should be generated"
    ),
    Option<String>(
        "lockfile",
        default: "",
        flag: "l",
        description: "The path to a lock file"
    ),
    Flag(
        "quiet",
        default: false,
        flag: "q",
        description: "Suppress printing of informational and success messages"
    ),
    Flag(
        "version",
        default: false,
        flag: "v",
        description: "Show XcodeGen version"
    ),
    generate
).run(version.description)
