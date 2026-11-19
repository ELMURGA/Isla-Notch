const vscode = require("vscode");
const { execFile } = require("child_process");
const os = require("os");
const path = require("path");

function activate(context) {
  const listener = vscode.tasks.onDidEndTaskProcess((event) => {
    if (!vscode.workspace.getConfiguration("isla").get("notifyWhenTaskEnds", true)) return;

    const task = event.execution.task;
    const project = vscode.workspace.workspaceFolders?.[0]?.name ?? "";
    const exitCode = event.exitCode;
    const succeeded = exitCode === 0;
    const title = succeeded
      ? "Tarea de VS Code terminada"
      : "Tarea de VS Code finalizada con error";
    const details = [task.name, project, exitCode == null ? null : `código ${exitCode}`]
      .filter(Boolean)
      .join(" · ");
    const notifyPath = path.join(
      os.homedir(),
      "Library",
      "Application Support",
      "Isla",
      "isla-notify"
    );

    execFile(notifyPath, ["--source", "vscode", title, details], { timeout: 2000 }, () => {});
  });

  context.subscriptions.push(listener);
}

function deactivate() {}

module.exports = { activate, deactivate };
