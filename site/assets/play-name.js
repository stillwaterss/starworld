"use strict";
const nameDialog = document.getElementById('name-dialog');
const nameField = document.getElementById('star-name');
let acceptName;
window.starworldEditName = (current, accept) => {
  if (nameDialog.open) return;
  acceptName = accept;
  nameField.value = current;
  nameDialog.showModal();
  nameField.focus();
  nameField.select();
};
nameField.addEventListener('keydown', event => {
  // Enter used to confirm an IME candidate must not also submit the name.
  if (event.key === 'Enter' && (event.isComposing || event.keyCode === 229)) event.preventDefault();
});
document.getElementById('name-form').addEventListener('submit', event => {
  event.preventDefault();
  const accept = acceptName;
  nameDialog.close();
  accept?.(nameField.value);
});
document.getElementById('cancel-name').addEventListener('click', () => nameDialog.close());
nameDialog.addEventListener('close', () => {
  acceptName = undefined;
  document.getElementById('canvas').focus();
});
