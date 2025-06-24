import consumer from "./consumer"

let editorChannel;

export function subscribeToEditor(projectId, fileId, branch, onReceive) {
  if (editorChannel) {
    editorChannel.unsubscribe();
  }

  editorChannel = consumer.subscriptions.create(
    {
      channel: "EditorChannel",
      project_id: projectId,
      file_id: fileId,
      branch: branch,
    },
    {
      received(data) {
        onReceive(data); // sync data to Monaco or show conflicts
      },
    }
  );
}

export function sendEditorUpdate(data) {
  if (editorChannel) {
    editorChannel.send(data);
  }
}
