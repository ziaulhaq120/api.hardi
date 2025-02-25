// Import Express
const express = require('express');
const app = express();

// Middleware untuk parsing JSON
app.use(express.json());

// Data sementara (sebagai contoh)
let data = [
    { id: 1, name: 'John Doe' },
    { id: 2, name: 'Jane Doe' }
];

// Route GET untuk mengambil semua data
app.get('/api/data', (req, res) => {
    res.json(data);
});

// Route GET untuk mengambil data berdasarkan ID
app.get('/api/data/:id', (req, res) => {
    const id = parseInt(req.params.id);
    const item = data.find(d => d.id === id);
    if (!item) return res.status(404).json({ message: 'Data not found' });
    res.json(item);
});

// Route POST untuk menambahkan data baru
app.post('/api/data', (req, res) => {
    const newItem = {
        id: data.length + 1,
        name: req.body.name
    };
    data.push(newItem);
    res.status(201).json(newItem);
});

// Route PUT untuk mengupdate data
app.put('/api/data/:id', (req, res) => {
    const id = parseInt(req.params.id);
    const item = data.find(d => d.id === id);
    if (!item) return res.status(404).json({ message: 'Data not found' });

    item.name = req.body.name;
    res.json(item);
});

// Route DELETE untuk menghapus data
app.delete('/api/data/:id', (req, res) => {
    const id = parseInt(req.params.id);
    data = data.filter(d => d.id !== id);
    res.json({ message: 'Data deleted' });
});

// Jalankan server
const PORT = 3000;
app.listen(PORT, () => {
    console.log(`Server running on http://localhost:${PORT}`);
});