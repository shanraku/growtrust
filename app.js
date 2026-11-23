const dialog = document.querySelector('#orderDialog');
const title = document.querySelector('#dialogTitle');
const status = document.querySelector('#dialogStatus');
let selectedService = '';
document.querySelectorAll('.order').forEach(button => {
  button.addEventListener('click', () => {
    selectedService = button.dataset.service || 'Service';
    title.textContent = selectedService;
    status.textContent = '';
    dialog.showModal();
  });
});
document.querySelector('#saveDemo').addEventListener('click', () => {
  const email = document.querySelector('#email').value.trim();
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    status.textContent = 'Please enter a valid email address or leave it blank.';
    return;
  }
  const requests = JSON.parse(localStorage.getItem('growtrust-demo-requests') || '[]');
  requests.push({ service: selectedService, email, createdAt: new Date().toISOString(), mode: 'demo-only' });
  localStorage.setItem('growtrust-demo-requests', JSON.stringify(requests));
  status.textContent = 'Demo request saved on this device only. No payment or real order was created.';
});
dialog.addEventListener('click', event => {
  if (event.target === dialog) dialog.close();
});