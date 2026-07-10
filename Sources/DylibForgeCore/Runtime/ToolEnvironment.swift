import Foundation

final class ToolEnvironment {
    let files: ProjectFiles
    let shell: CommandExecutor

    init(files: ProjectFiles = ProjectFiles(), shell: CommandExecutor = CommandExecutor()) {
        self.files = files
        self.shell = shell
    }
}
