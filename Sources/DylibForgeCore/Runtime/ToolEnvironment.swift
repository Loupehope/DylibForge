import DylibForgeSubprocess
import Foundation

final class ToolEnvironment {
    let files: ProjectFiles
    let shell: CommandExecutor

    init(files: ProjectFiles = ProjectFiles(), shell: CommandExecutor) {
        self.files = files
        self.shell = shell
    }
}
