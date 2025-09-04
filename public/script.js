// (O código do script.js é o mesmo da resposta anterior, sem alterações)
document.addEventListener('DOMContentLoaded', () => {
    // --- Referências aos Elementos da UI ---
    const collectionsList = document.getElementById('collections-list');
    const documentsList = document.getElementById('documents-list');
    const fieldsContent = document.getElementById('fields-content');
    const startCollectionBtn = document.getElementById('start-collection-btn');
    const addDocumentBtn = document.getElementById('add-document-btn');
    const addFieldBtn = document.getElementById('add-field-btn');
    const addCollectionModal = document.getElementById('add-collection-modal-overlay');
    const addCollectionForm = document.getElementById('add-collection-form');
    const addDocumentModal = document.getElementById('add-document-modal-overlay');
    const addDocumentForm = document.getElementById('add-document-form');
    const modalFieldsContainer = document.getElementById('modal-fields-container');
    const addMoreFieldsBtn = document.getElementById('add-more-fields-btn');
    const confirmDeleteModal = document.getElementById('confirm-delete-modal-overlay');

    // --- Lógica de troca de input booleano ---
    function handleTypeChange(event) {
        const selectType = event.target;
        const parentRow = selectType.closest('.field-row, .add-field-form');
        const valueInput = parentRow.querySelector('[name="value"], .add-value');

        if (selectType.value === 'boolean') {
            if (valueInput.tagName === 'INPUT') {
                const selectValue = document.createElement('select');
                selectValue.name = valueInput.name || 'value';
                selectValue.className = valueInput.className;
                selectValue.innerHTML = `<option value="true">true</option><option value="false">false</option>`;
                valueInput.replaceWith(selectValue);
            }
        } else {
            if (valueInput.tagName === 'SELECT') {
                const textInput = document.createElement('input');
                textInput.type = 'text';
                textInput.name = valueInput.name || 'value';
                textInput.className = valueInput.className;
                textInput.placeholder = 'Value';
                if(valueInput.required) textInput.required = true;
                valueInput.replaceWith(textInput);
            }
        }
    }
    modalFieldsContainer.addEventListener('change', (e) => {
        if (e.target.name === 'type') handleTypeChange(e);
    });
    fieldsContent.addEventListener('change', (e) => {
        if (e.target.classList.contains('add-type')) handleTypeChange(e);
    });

    // --- Resto do script (sem mudanças) ---
    // (O restante do script.js é idêntico à resposta anterior)
    let state = { collections: [], documents: [], selectedCollection: null, selectedDocumentId: null };
    const init = () => {
        const currentCollectionTitle = document.getElementById('current-collection-title');
        const currentDocumentTitle = document.getElementById('current-document-title');
        const confirmDeleteMessage = document.getElementById('confirm-delete-message');
        const confirmDeleteBtn = document.getElementById('confirm-delete-confirm-btn');
        const cancelDeleteBtn = document.getElementById('confirm-delete-cancel-btn');
        renderAll = () => { renderCollections(); renderDocuments(); renderFields(); }
        renderCollections = () => {
            collectionsList.innerHTML = '';
            state.collections.sort().forEach(name => {
                const li = document.createElement('li');
                li.dataset.collectionName = name;
                li.innerHTML = `<span>${name}</span><button class="delete-btn" title="Delete collection">🗑️</button>`;
                if (name === state.selectedCollection) li.classList.add('selected');
                collectionsList.appendChild(li);
            });
        };
        renderDocuments = () => {
            documentsList.innerHTML = '';
            currentCollectionTitle.textContent = state.selectedCollection || 'Selecione uma coleção';
            addDocumentBtn.disabled = !state.selectedCollection;
            state.documents.forEach(doc => {
                const li = document.createElement('li');
                li.dataset.docId = doc.id;
                if (doc.id === state.selectedDocumentId) li.classList.add('selected');
                li.innerHTML = `<span>${doc.id}</span><button class="delete-btn" title="Delete document">🗑️</button>`;
                documentsList.appendChild(li);
            });
        };
        renderFields = () => {
            fieldsContent.innerHTML = '';
            addFieldBtn.disabled = !state.selectedDocumentId;
            if (!state.selectedDocumentId) {
                currentDocumentTitle.textContent = 'Selecione um documento';
                return;
            }
            currentDocumentTitle.textContent = state.selectedDocumentId;
            const doc = state.documents.find(d => d.id === state.selectedDocumentId);
            if (doc) {
                for (const [key, value] of Object.entries(doc)) {
                    const type = typeof value;
                    const fieldDiv = document.createElement('div');
                    fieldDiv.className = 'field-item';
                    fieldDiv.innerHTML = `<span class="field-key">"${key}"</span><span class="field-separator">:</span><span class="field-value">${JSON.stringify(value)}</span><span class="field-type">${type}</span>`;
                    fieldsContent.appendChild(fieldDiv);
                }
            }
        };
        fetchCollections = async () => {
            const response = await fetch('/api/collections');
            state.collections = await response.json();
            renderCollections();
        };
        fetchDocuments = async (collectionName) => {
            const response = await fetch(`/api/${collectionName}`);
            state.documents = response.ok ? await response.json() : [];
            renderDocuments();
        };
        updateDocument = async (collectionName, docId, data) => {
            await fetch(`/api/${collectionName}/${docId}`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
            await fetchDocuments(collectionName);
            renderFields();
        };
        setupModal = (modal) => {
            const cancelBtns = modal.querySelectorAll('.cancel-btn');
            modal.addEventListener('click', (e) => { if (e.target === modal) hideModal(modal); });
            cancelBtns.forEach(btn => btn.addEventListener('click', () => hideModal(modal)));
        };
        showModal = (modal) => modal.classList.remove('hidden');
        hideModal = (modal) => modal.classList.add('hidden');
        addFieldRow = () => {
            const firstRow = modalFieldsContainer.querySelector('.field-row');
            const newRow = firstRow.cloneNode(true);
            newRow.querySelectorAll('input, select').forEach(el => {
                if (el.type !== 'select-one') el.value = ''; else el.value = 'string';
            });
            const valueInput = newRow.querySelector('[name="value"]');
            if (valueInput.tagName === 'SELECT') {
                const newInput = document.createElement('input');
                newInput.type = 'text'; newInput.name = 'value'; newInput.placeholder = 'Value'; newInput.required = true;
                valueInput.replaceWith(newInput);
            }
            newRow.querySelector('.delete-field-btn').classList.remove('hidden');
            modalFieldsContainer.appendChild(newRow);
        };
        showConfirmationDialog = (message) => {
            return new Promise((resolve) => {
                confirmDeleteMessage.textContent = message;
                showModal(confirmDeleteModal);
                confirmDeleteBtn.onclick = () => { hideModal(confirmDeleteModal); resolve(true); };
                cancelDeleteBtn.onclick = () => { hideModal(confirmDeleteModal); resolve(false); };
            });
        };
        startCollectionBtn.addEventListener('click', () => {
            while (modalFieldsContainer.children.length > 1) { modalFieldsContainer.removeChild(modalFieldsContainer.lastChild); }
            addCollectionForm.reset();
            handleTypeChange({ target: addCollectionForm.querySelector('[name="type"]') });
            showModal(addCollectionModal);
        });
        addMoreFieldsBtn.addEventListener('click', addFieldRow);
        addCollectionForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            const collectionId = document.getElementById('collection-id').value.trim();
            let documentId = document.getElementById('document-id').value.trim();
            if (!collectionId) return alert('O ID da coleção é obrigatório.');
            const newDoc = {};
            const fieldRows = modalFieldsContainer.querySelectorAll('.field-row');
            for (const row of fieldRows) {
                const key = row.querySelector('[name="key"]').value.trim();
                const type = row.querySelector('[name="type"]').value;
                let value = row.querySelector('[name="value"]').value;
                if (key && value !== '') {
                    if (type === 'number') value = parseFloat(value);
                    if (type === 'boolean') value = (value === 'true');
                    newDoc[key] = value;
                }
            }
            if (Object.keys(newDoc).length === 0) return alert('Adicione pelo menos um campo válido.');
            if (documentId) newDoc.id = documentId;
            const response = await fetch(`/api/${collectionId}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(newDoc) });
            if (response.ok) {
                hideModal(addCollectionModal);
                await fetchCollections();
                state.selectedCollection = collectionId;
                state.selectedDocumentId = null;
                await fetchDocuments(collectionId);
                renderAll();
            } else { alert('Erro ao criar coleção.'); }
        });
        collectionsList.addEventListener('click', async (e) => {
            const parentLi = e.target.closest('li');
            if (!parentLi) return;
            if (e.target.classList.contains('delete-btn')) {
                const collectionToDelete = parentLi.dataset.collectionName;
                const confirmed = await showConfirmationDialog(`Tem certeza que deseja deletar a coleção INTEIRA "${collectionToDelete}"? Todos os documentos dentro dela serão perdidos permanentemente.`);
                if (confirmed) {
                    await fetch(`/api/${collectionToDelete}`, { method: 'DELETE' });
                    if (state.selectedCollection === collectionToDelete) {
                        state.selectedCollection = null; state.selectedDocumentId = null; state.documents = [];
                        renderAll();
                    }
                    await fetchCollections();
                }
            } else {
                state.selectedCollection = parentLi.dataset.collectionName;
                state.selectedDocumentId = null; state.documents = [];
                await fetchDocuments(state.selectedCollection);
                renderAll();
            }
        });
        addDocumentBtn.addEventListener('click', () => {
            document.getElementById('doc-modal-collection-id').value = state.selectedCollection;
            addDocumentForm.reset(); showModal(addDocumentModal);
        });
        addDocumentForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            const docId = document.getElementById('doc-modal-document-id').value.trim();
            const dataJson = document.getElementById('doc-modal-data').value;
            try {
                const data = JSON.parse(dataJson);
if(docId) data.id = docId;
                const response = await fetch(`/api/${state.selectedCollection}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data) });
                if (response.ok) {
                    hideModal(addDocumentModal);
                    await fetchDocuments(state.selectedCollection);
                } else { alert('Erro ao adicionar documento.'); }
            } catch(err) { alert('JSON inválido!'); }
        });
        documentsList.addEventListener('click', async (e) => {
            const target = e.target;
            if (target.classList.contains('delete-btn')) {
                const docIdToDelete = target.closest('li').dataset.docId;
                const confirmed = await showConfirmationDialog(`Tem certeza que deseja deletar o documento "${docIdToDelete}"? Esta ação não pode ser desfeita.`);
                if (confirmed) {
                    await fetch(`/api/${state.selectedCollection}/${docIdToDelete}`, { method: 'DELETE' });
                    if (state.selectedDocumentId === docIdToDelete) {
                        state.selectedDocumentId = null; renderFields();
                    }
                    await fetchDocuments(state.selectedCollection);
                }
            } else if (target.closest('li')) {
                state.selectedDocumentId = target.closest('li').dataset.docId;
                renderDocuments(); renderFields();
            }
        });
        addFieldBtn.addEventListener('click', () => {
            if(document.querySelector('.add-field-form')) return;
            const form = document.createElement('div');
            form.className = 'add-field-form';
            form.innerHTML = `<input type="text" placeholder="Field Key" class="add-key"><select class="add-type"><option value="string">string</option><option value="number">number</option><option value="boolean">boolean</option></select><input type="text" placeholder="Value" class="add-value"><button class="save-btn">✓</button><button class="cancel-btn">X</button>`;
            fieldsContent.prepend(form);
            form.querySelector('.cancel-btn').addEventListener('click', () => form.remove());
            form.querySelector('.save-btn').addEventListener('click', async () => {
                const key = form.querySelector('.add-key').value.trim();
                const type = form.querySelector('.add-type').value;
                let value = form.querySelector('.add-value').value;
                if(!key || value === '') returfn;
                if (type === 'number') value = parseFloat(value);
                if (type === 'boolean') value = (value === 'true');
                const doc = state.documents.find(d => d.id === state.selectedDocumentId);
                const updatedDoc = { ...doc, [key]: value };
                await updateDocument(state.selectedCollection, state.selectedDocumentId, updatedDoc);
            });
        });
        setupModal(addCollectionModal);
        setupModal(addDocumentModal);
        fetchCollections();
    };
    init();
});